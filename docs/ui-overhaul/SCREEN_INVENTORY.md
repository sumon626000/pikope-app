# Screen inventory (source of truth)

PikoPe / DuelX Flutter client (`lib/`). Last updated: Phase 8 final audit (2026-11-02).

Legend: **Route** = full-screen navigation; **Overlay** = modal/banner/in-match UI; **Shell** = wraps many routes; **Conditional** = platform or state gated.

---

## 1. App shell & bootstrap

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-01 | BilliardPokerApp | Shell | `lib/app_bootstrap.dart` | `main()` |
| S-02 | WebLandscapeGate | Conditional shell | `lib/core/web_play.dart` | Web: portrait hint, landscape fullscreen |
| S-03 | WebApkPromoHost | Shell | `lib/core/web_apk_promo.dart` | Web: APK download chip |
| S-04 | ChallengeInboxHost | Shell | `lib/features/duel/challenge_inbox_host.dart` | Global challenge poll + incoming UI |
| S-05 | ZiniPayReturnHost | Shell | `lib/features/duel/zinipay_return.dart` | Web return URL handling |
| S-06 | ErrorWidget (release) | Conditional | `lib/app_bootstrap.dart` | Uncaught widget errors |

## 2. Start / auth / updates

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-10 | AppStartGate | Route | `lib/features/start/app_start_gate.dart` | App `home` |
| S-11 | MandatoryUpdateScreen | Conditional route | `lib/features/start/app_update_io.dart` / stub | Block play if APK update required |
| S-12 | LoadingScreen | Route | `lib/features/start/loading_screen.dart` | After update check |
| S-13 | LoginScreen | Route / modal | `lib/features/start/login_screen.dart` | Full screen or `popOnSuccess` from auth prompt |
| S-14 | ForgotPasswordScreen | Route | `lib/features/start/forgot_password_screen.dart` | From login |
| S-15 | CreateProfileScreen | Route (orphan) | `lib/features/duel/create_profile_screen.dart` | **No navigators found** — dead entry? |

## 3. Main lobby & hubs

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-20 | DuelHomeScreen | Route | `lib/features/duel/duel_home_screen.dart` | `homeScreenFor()` after loading |
| S-21 | PoolHubScreen | Route | `lib/features/duel/pool_hub_screen.dart` | Home → Pool |
| S-22 | LudoLobbyScreen | Route | `lib/features/ludo/ludo_lobby_screen.dart` | Home → Ludo |
| S-23 | CarromLobbyScreen | Route | `lib/features/carrom/carrom_lobby_screen.dart` | Home → Carrom |
| S-24 | HomeScreen | Route (legacy) | `lib/features/home/home_screen.dart` | **Tests / old poker entry only** |

## 4. Stakes, matchmaking, online

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-30 | BetLevelScreen | Route | `lib/features/duel/bet_level_screen.dart` | Hubs, friends, challenge |
| S-31 | MatchmakingScreen | Route | `lib/features/duel/matchmaking_screen.dart` | Bet level → play |
| S-32 | OnlineLobbyScreen | Route | `lib/features/online/online_screens.dart` | Friends / private room |
| S-33 | RoomScreen | Route | `lib/features/online/online_screens.dart` | Room join / rematch |
| S-34 | AccountScreen | Route | `lib/features/online/online_screens.dart` | Online lobby → account |
| S-35 | LobbyScreen | Route | `lib/features/lobby/lobby_screen.dart` | Legacy HomeScreen → poker bots |
| S-36 | ChallengeScreen | Route | `lib/features/duel/challenge_screen.dart` | Home nav |
| S-37 | ChallengeGamePickScreen | Route | `lib/features/duel/challenge_screen.dart` | Pick game vs player |
| S-38 | ChallengeWaitScreen | Route | `lib/features/duel/challenge_flow.dart` | After send challenge |

## 5. Gameplay

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-40 | PoolScreen | Route | `lib/features/pool/pool_screen.dart` | Practice / online pool |
| S-41 | LudoScreen | Route | `lib/features/ludo/ludo_screen.dart` | Practice / online ludo |
| S-42 | CarromScreen | Route | `lib/features/carrom/carrom_screen.dart` | Practice / online carrom |
| S-43 | GameScreen | Route | `lib/features/game/game_screen.dart` | Billiard poker (legacy path) |

## 6. Economy, shop, items

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-50 | ShopScreen | Route | `lib/features/duel/shop_screen.dart` | Top bar / nav / prompts |
| S-51 | ZiniPayCheckoutScreen | Route | `lib/features/duel/zini_pay_checkout.dart` | Shop deposit flow |
| S-52 | ItemsScreen | Route | `lib/features/duel/items_screen.dart` | Home nav |
| S-53 | CuesScreen | Route | `lib/features/duel/cues_screen.dart` | Items → cues |
| S-54 | BoardShopScreen | Route | `lib/features/duel/board_shop.dart` | Items / shop boards |
| S-55 | CoinTutorialPlayerScreen | Route | `lib/features/duel/coin_tutorial_video.dart` | Shop tutorials |

## 7. Profile, settings, social, data

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| S-60 | SettingsScreen | Route | `lib/features/misc/settings_screen.dart` | Top bar |
| S-61 | LeaderboardScreen | Route | `lib/features/misc/leaderboard_screen.dart` | Home nav |
| S-62 | HistoryScreen | Route | `lib/features/duel/history_screen.dart` | Home nav (Match data) |
| S-63 | ReferScreen | Route | `lib/features/duel/refer_screen.dart` | Home refer |
| S-64 | NoticesScreen | Route | `lib/features/duel/notices_screen.dart` | Mail icon |
| S-65 | NotificationsScreen | Route | `lib/features/duel/notifications_screen.dart` | Bell icon |
| S-66 | HowToPlayScreen | Route | `lib/features/misc/how_to_play_screen.dart` | Home banner / in-game rules |
| S-67 | LegalScreen | Route | `lib/features/misc/legal_screen.dart` | Login / settings (privacy, terms, conditions) |

## 8. Shared layout primitives (affect many screens)

| ID | Name | Type | Primary file | Notes |
|----|------|------|--------------|-------|
| P-01 | DuelCanvas | Layout | `lib/core/duel_ui.dart` | Fixed **1600×900** + `FittedBox` |
| P-02 | DuelPage | Layout | `lib/features/duel/duel_chrome.dart` | DuelCanvas + top bar + back |
| P-03 | PageFrame | Layout | `lib/features/misc/page_frame.dart` | Used by settings, online, leaderboard |
| P-04 | DuelTopBar | Chrome | `lib/features/duel/duel_chrome.dart` | Logo, profile, coins, shortcuts |
| P-05 | GameCard / NavTile / HomeBanner | Components | `lib/features/duel/duel_home_screen.dart` | Home & hubs |
| P-06 | GameButton / DuelButton | Components | `lib/core/widgets.dart`, `duel_ui.dart` | Mixed usage |
| P-07 | showDuelDialog / showDuelMessage | Dialog system | `lib/core/duel_ui.dart` | Scaled like DuelCanvas |

## 9. Dialogs, popups, banners (non-route)

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| D-01 | Login required (auth prompt) | Dialog | `lib/features/start/auth_prompt.dart` | Protected actions |
| D-02 | Daily bonus dialog | Dialog | `lib/features/duel/duel_home_screen.dart` | `_DailyBonusDialog` |
| D-03 | Home chooser dialogs | Dialog | `lib/features/duel/duel_home_screen.dart` | Practice / friends |
| D-04 | Practice mode dialog | Dialog | `lib/features/duel/practice_launch.dart` | Offline practice |
| D-05 | Not enough balance | Dialog | `lib/features/duel/not_enough_balance.dart` | Stakes / shop |
| D-06 | Incoming challenge banner | Banner/dialog | `lib/features/duel/challenge_incoming_banner.dart` | ChallengeInboxHost |
| D-07 | Logout confirm | Dialog | `lib/features/misc/settings_screen.dart` | Settings |
| D-08 | Cue purchase confirm | Dialog | `lib/features/duel/cues_screen.dart` | Cues shop |
| D-09 | Transfer confirm | Dialog | `lib/features/duel/coin_transfer_tab.dart` | Shop transfer tab |
| D-10 | Bet level clubs/friends messages | Dialog | `lib/features/duel/bet_level_screen.dart` | Nav tiles |
| D-11 | Pool hub / game messages | Dialog | `lib/features/duel/bet_level_screen.dart` | `showOfflinePracticeModeDialog` |
| D-12 | Match result / jackpot / reveal | Overlay | `lib/features/duel/match_overlays.dart` | In-match |
| D-13 | Web portrait / fullscreen hints | Overlay | `lib/core/web_play.dart` | Mobile web |

## 10. Web HTML (pre-Flutter)

| ID | Name | Type | Primary file | Entry / trigger |
|----|------|------|--------------|-----------------|
| W-01 | index.html splash | Static | `pikope-web/web/index.html` | First paint before Flutter |

---

## Counts (for PROGRESS)

| Category | Count |
|----------|------:|
| Full routes (S-xx, excluding orphan/legacy) | **42** |
| Shell / conditional shells | **6** |
| Layout primitives | **7** |
| Dialogs / overlays | **13** |
| Web HTML splash | **1** |
| **Total tracked UI surfaces** | **69** |

Orphan / legacy (audit separately, do not delete without product sign-off): S-15, S-24, S-35, S-43.
