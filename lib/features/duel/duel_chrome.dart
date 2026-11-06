import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/app_theme.dart';
import '../../core/audio_service.dart';
import '../../core/design/design.dart';
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
    if (DesignBreakpoints.portraitLayout(context)) {
      return _portraitBar(context, ref, t, settings, unread, registered, coins);
    }
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
                      border: registered
                          ? null
                          : Border.all(color: DuelColors.rimLight, width: 2),
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
                          : const Icon(
                              Icons.person_rounded,
                              color: DuelColors.silver,
                              size: 44,
                            ),
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
                          registered
                              ? settings.name.toUpperCase()
                              : t.browseProfileTitle,
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
            _TopIcon(Icons.settings_rounded, () => _profileTap(context, ref)),
          ],
          const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _portraitBar(
    BuildContext context,
    WidgetRef ref,
    AppStrings t,
    AppSettings settings,
    int unread,
    bool registered,
    int? coins,
  ) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 8),
          const DuelLogo(height: 30),
          const SizedBox(width: 8),
          if (showProfile)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AudioService.tap();
                  _profileTap(context, ref);
                },
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: DuelColors.rimLight,
                          width: 1.4,
                        ),
                      ),
                      child: ClipOval(
                        child: registered
                            ? AvatarImage(settings.avatar, size: 32)
                            : const Icon(
                                Icons.person_rounded,
                                color: DuelColors.silver,
                                size: 18,
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        registered
                            ? settings.name.toUpperCase()
                            : t.browseProfileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(
                          12,
                          color: DuelColors.silver,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          _PortraitWallet(
            coins: coins,
            placeholder: t.signUpOrLogin,
            onTap: () {
              AudioService.tap();
              _walletTap(context, ref);
            },
          ),
          if (showShortcuts) ...[
            _PortraitIcon(Icons.mail_rounded, () async {
              if (!await requireRegisteredAccount(context, ref)) return;
              if (context.mounted) pushScreen(context, const NoticesScreen());
            }),
            _PortraitIcon(Icons.notifications_rounded, () async {
              if (!await requireRegisteredAccount(context, ref)) return;
              if (context.mounted)
                pushScreen(context, const NotificationsScreen());
            }, badge: unread),
            _PortraitIcon(
              Icons.settings_rounded,
              () => _profileTap(context, ref),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _PortraitWallet extends StatelessWidget {
  const _PortraitWallet({
    required this.coins,
    required this.placeholder,
    required this.onTap,
  });

  final int? coins;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = coins != null
        ? formatCoins(coins!, compact: true)
        : placeholder;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        constraints: const BoxConstraints(maxWidth: 118),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xEE12182E),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: DuelColors.rimLight.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PikoCoinIcon(size: 18),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(
                  11,
                  color: Colors.white,
                  weight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.add_rounded, color: Color(0xFFFF8A3C), size: 16),
          ],
        ),
      ),
    );
  }
}

class _PortraitIcon extends StatelessWidget {
  const _PortraitIcon(this.icon, this.onTap, {this.badge = 0});

  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: DuelColors.silver, size: 20),
          if (badge > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: DuelColors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: AppText.label(
                    8,
                    color: Colors.white,
                    weight: FontWeight.w900,
                  ),
                ),
              ),
            ),
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

/// Page frame of the secondary lobby screens (shop, cues, history ...):
/// top bar, a title, the content, and BACK in the corner.
class DuelPage extends ConsumerWidget {
  const DuelPage({
    super.key,
    required this.title,
    required this.child,
    this.sub,
    this.expanded = false,
    this.sideBack = false,
    this.contentTop,
  });

  final String title;
  final String? sub;
  final Widget child;

  /// Use almost the full canvas (shop add-cash / redeem).
  final bool expanded;

  /// BACK sits on the left side, clear of the shop cards.
  final bool sideBack;

  /// Extra clearance below [DuelTitle] + subtitle (shop / items tabs).
  final double? contentTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    if (DesignBreakpoints.portraitLayout(context)) {
      return _PortraitDuelPage(title: title, sub: sub, child: child);
    }
    final bodyTop = DesignSecondaryPage.bodyTop(
      expanded: expanded,
      override: contentTop,
    );
    final backTop = DesignSecondaryPage.backTop(
      expanded: expanded,
      sideBack: sideBack,
      contentTop: contentTop,
    );
    final pad = DesignSecondaryPage.contentPadding(
      expanded: expanded,
      sideBack: sideBack,
    );
    return DuelCanvas(
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: DuelTopBar(showProfile: false, showShortcuts: false),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: DesignSecondaryPage.titleTop,
            child: Center(child: DuelTitle(title, size: 44, sub: sub)),
          ),
          Positioned(
            left: pad.left,
            right: pad.right,
            top: bodyTop,
            bottom: pad.bottom,
            child: child,
          ),
          if (sideBack)
            Positioned(
              left: DesignSecondaryPage.backSideLeft,
              top: backTop,
              child: NavTile(
                icon: Icons.reply_rounded,
                label: t.navBack,
                onTap: () => Navigator.of(context).pop(),
              ),
            )
          else
            Positioned(
              left: DesignSecondaryPage.backLeft,
              bottom: DesignLayout.bottomBarInset,
              child: NavTile(
                icon: Icons.reply_rounded,
                label: t.navBack,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Secondary lobby pages on a portrait phone: real pixels, back, title, wallet.
class _PortraitDuelPage extends ConsumerWidget {
  const _PortraitDuelPage({required this.title, this.sub, required this.child});

  final String title;
  final String? sub;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final coins = lobbyDisplayCoins(ref);
    return Scaffold(
      backgroundColor: DuelColors.ink,
      resizeToAvoidBottomInset: true,
      body: DuelBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 8, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DuelColors.rimLight),
                            color: const Color(0xCC0B0E1C),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: DuelColors.silver,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const DuelLogo(height: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(15, weight: FontWeight.w900),
                          ),
                          if (sub != null)
                            Text(
                              sub!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(
                                10,
                                color: DuelColors.dim,
                                weight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _PortraitWallet(
                      coins: coins,
                      placeholder: t.signUpOrLogin,
                      onTap: () async {
                        AudioService.tap();
                        if (!await requireRegisteredAccount(context, ref))
                          return;
                        if (context.mounted)
                          pushScreen(context, const ShopScreen());
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
