part of 'duel_home_screen.dart';

extension _PortraitHome on _DuelHomeScreenState {
  Widget buildPortraitHome() {
    final t = ref.watch(stringsProvider);
    final lobby = ref.watch(lobbyProvider);
    final session = ref.watch(sessionProvider);
    final registered = hasRegisteredAccount(ref);
    final active = ref.watch(activeMatchProvider).valueOrNull;
    final challengePending = ref.watch(challengePendingCountProvider) > 0;
    final data = lobby.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DuelTopBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Column(
            children: [
              Text(
                t.chooseTable,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(
                  20,
                  color: Colors.white,
                  weight: FontWeight.w900,
                ),
              ),
              Text(
                t.pickGameDuel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(
                  11,
                  color: DuelColors.dim,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Expanded(
                  child: PortraitGameRow(
                    color: DuelColors.green,
                    title: t.poolTitle,
                    subtitle: t.poolSub,
                    art: const BilliardArt(),
                    playLabel: t.playNow,
                    onPlay: () => _open(const PoolHubScreen()),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: PortraitGameRow(
                    color: DesignColors.ludoAccent,
                    title: t.ludoTitle,
                    subtitle: t.ludoSub,
                    art: const LudoArt(),
                    playLabel: t.playNow,
                    onPlay: () => _open(const LudoLobbyScreen()),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: PortraitGameRow(
                    color: DesignColors.carromAccent,
                    title: t.carromTitle,
                    subtitle: t.carromSub,
                    art: const CarromArt(),
                    playLabel: t.playNow,
                    onPlay: () => _open(const CarromLobbyScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (lobby.hasError && data == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              lobby.error is ApiException
                  ? t.maybeApi((lobby.error as ApiException).message)
                  : t.offlineServer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(11, color: DuelColors.red),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.redeem_rounded,
                          title: t.dailyBonus,
                          accent: DuelColors.gold,
                          badge: data?.daily.available ?? false,
                          attention: data?.daily.available ?? false,
                          subtitle: data == null
                              ? null
                              : data.daily.available
                              ? t.claimNow
                              : null,
                          onTap: data == null ? null : () => _daily(data.daily),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.emoji_events_rounded,
                          title: t.rank,
                          accent: DuelColors.gold,
                          subtitle: registered
                              ? session.rankName
                              : t.browseProfileTitle,
                          onTap: () => _open(const LeaderboardScreen()),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.flag_rounded,
                          title: t.mission,
                          accent: const Color(0xFF8EDB5A),
                          onTap: () => showDuelMessage(
                            context,
                            title: t.missions,
                            body: t.missionsBody,
                            icon: Icons.flag_rounded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.menu_book_rounded,
                          title: t.howToPlayTitle,
                          accent: const Color(0xFFC9B8FF),
                          subtitle: t.howToPlaySub,
                          onTap: () => _open(const HowToPlayScreen()),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.smart_toy_rounded,
                          title: t.practiceFreeTitle,
                          accent: const Color(0xFF9BF2B5),
                          subtitle: t.practiceFreeSub,
                          onTap: _practice,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: PortraitFeatureTile(
                          icon: Icons.groups_rounded,
                          title: t.friendsBannerTitle,
                          accent: const Color(0xFF9CC2FF),
                          subtitle: t.friendsBannerSub,
                          onTap: _friends,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: active != null
              ? HighlightPulse(
                  highlightColor: DuelColors.gold,
                  onTap: () {
                    AudioService.tap();
                    _rejoin(active);
                  },
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: duelPanel(radius: 12, rim: DuelColors.gold),
                    child: Text(
                      t.rejoinMatch,
                      style: AppText.label(
                        13,
                        color: DuelColors.gold,
                        weight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              : Row(
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      color: DuelColors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.online,
                      style: AppText.label(11, color: DuelColors.dim),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lobby.hasError && data == null
                          ? t.offline
                          : (data == null ? '...' : formatCoins(data.online)),
                      style: AppText.label(
                        13,
                        color: DuelColors.silver,
                        weight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    if (data != null && !data.daily.available)
                      _Countdown(
                        from: data.fetchedAt,
                        seconds: data.daily.secondsToNext,
                      ),
                  ],
                ),
        ),
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            children: [
              NavTile(
                icon: Icons.card_giftcard_rounded,
                label: t.refer,
                onTap: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await _open(const ReferScreen());
                },
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.home_rounded,
                label: t.navHome,
                active: true,
                onTap: _reload,
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.storefront_rounded,
                label: t.navShop,
                onTap: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await _open(const ShopScreen());
                },
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.leaderboard_rounded,
                label: t.navRankings,
                onTap: () => _open(const LeaderboardScreen()),
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.backpack_rounded,
                label: t.navItems,
                onTap: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await _open(const ItemsScreen());
                },
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.groups_rounded,
                label: t.navFriends,
                onTap: _friends,
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.sports_kabaddi_rounded,
                label: t.navChallenge,
                badge: challengePending,
                onTap: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await _open(const ChallengeScreen());
                },
              ),
              const SizedBox(width: 6),
              NavTile(
                icon: Icons.query_stats_rounded,
                label: t.navData,
                onTap: () async {
                  if (!await requireRegisteredAccount(context, ref)) return;
                  if (mounted) await _open(const HistoryScreen());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
