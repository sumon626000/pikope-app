# Billiard Poker

Four pool games in one Flutter app (Android, landscape):

| Game | Players | Source |
|---|---|---|
| **Billiard Poker** | 4, free for all - 7 poker cards decide your balls | `Rules Billiard Poker.pdf` |
| **8-Ball** | 1 v 1 - solids vs stripes, call the pocket for the 8 | `Rules of Billiards.pdf` |
| **9-Ball** | 1 v 1 - lowest ball first, the 9 wins | `Rules of Billiards.pdf` |
| **10-Ball** | 1 v 1 - lowest ball first, the 10 wins | `Rules of Billiards.pdf` |

The game is picked on the home screen; all four share the table, physics,
aiming, power bar, bots and table skins.

Every game is playable **offline** (bots, or pass & play on one device) and
**online** against other players through the PHP backend in [`backend/`](backend/).
A build made without `API_BASE_URL` is offline-only.

## Run

```bash
flutter pub get
flutter run                 # offline only
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # with a local backend (emulator)
flutter test                # rules, physics, full-match and widget tests
flutter build apk --release   # requires android/key.properties (see android/key.properties.example)
flutter build appbundle --release
```

## Layout

```
lib/
  game/        Pure Dart, no Flutter imports - portable to a server
    models/    PlayingCard, HandCard, PlayerState, MatchState, ShotResult
    rules/     RulesEngine: break draw, deal, shot verdicts, penalties, declare
    physics/   PhysicsWorld: fixed-step balls, cushions, pockets, aim prediction
    ai/        BotPlayer: ghost-ball candidates tested on a cloned world
    pool/      PoolRules + PoolBot: 8-Ball, 9-Ball, 10-Ball
  core/        Theme, env, audio, CloudinaryService, settings/profile state
  data/        Demo content, local storage
  features/
    home/ lobby/ misc/   Menus, match setup, settings, leaderboard, rules
    game/                Billiard Poker: GameController, table, HUD, overlays
    pool/                8/9/10-Ball: PoolController + PoolScreen (same table widgets)
test/          Unit, integration (full bot matches) and widget tests
test_tools/    Screenshot renderer for visual review
backend/       PHP + MySQL server: accounts, rooms, authoritative online play
test_online/   Online matches against a running backend; stand-in opponents
docs/          Analysis, decisions, schema, design mapping, setup, assets
```

## Documents

- [docs/PROJECT_ANALYSIS.md](docs/PROJECT_ANALYSIS.md) - what the client documents specify
- [docs/PROJECT_DECISIONS.md](docs/PROJECT_DECISIONS.md) - rule gaps and how they were filled (**needs client confirmation**)
- [docs/DESIGN_MAPPING.md](docs/DESIGN_MAPPING.md) - mockup -> screen mapping
- [docs/BACKEND.md](docs/BACKEND.md) and [backend/README.md](backend/README.md) - PHP backend, API, trust model
- [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) - build, config, release
- [docs/MISSING_ASSETS.md](docs/MISSING_ASSETS.md) - placeholder and missing assets
