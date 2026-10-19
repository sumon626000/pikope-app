# Backend

The backend is a custom **PHP + MySQL** service in [`backend/`](../backend/)
(the client chose this over Firebase). Its README covers installation, the
API, the shot protocol and the trust model:
[backend/README.md](../backend/README.md). Deployment steps:
[backend/deploy/DEPLOY.md](../backend/deploy/DEPLOY.md).

The server simulates every shot itself (`backend/src/Game/Physics.php`, a
port of the app's physics that the online tests check bit for bit).

## Tables (`backend/sql/schema.sql`)

| Table | Holds |
|---|---|
| `users` | profile, coins, wins, games; guests have no email |
| `auth_tokens` | SHA-256 of each bearer token, expiry |
| `login_attempts`, `rate_limits` | throttling of sign-in, sign-up, reset |
| `password_resets` | hashed one-time reset codes |
| `rooms`, `room_players` | lobbies: code, game, seats, heartbeat |
| `games` | one row per match: version + full authoritative state (JSON) |
| `game_players` | who sits where |
| `game_shots` | every shot: inputs, reported outcome, ruling |
| `match_results` | per-player result and coins, online or vs bots |

## What the app sends and receives

The app talks to it through `lib/data/api_client.dart`; an online match is
driven by `lib/features/online/game_link.dart` - over a WebSocket
(`realtime_socket.dart`), falling back to HTTP polling every 0.6 s - and the
two match controllers in online mode. The server's state for Billiard Poker is
filtered per player: other hands, the penalty pile and unrevealed break cards
never leave the server.

## Not built

- Friends list, chat, in-app purchases.
- Verification of offline (bot) match results - see the trust model.

## Economy (bet levels, wallet, shop)

`src/Economy.php` holds the money rules; its numbers live in the `settings`
table (key `economy`) and are edited on `/admin` (Economy section).

| Endpoint | What it does |
|---|---|
| `GET /lobby` | wallet, bet levels of both modes (buy-in, prize), players per level, daily bonus state, cue shop |
| `POST /rooms/quick {game: "billiard"\|"poker", level}` | queue at a bet level; the buy-in is checked now and taken when the room fills |
| `POST /daily/claim` | today's step of the bonus ladder |
| `POST /cues/buy {id}` / `POST /me/cue {id}` | buy / equip a cue |
| `GET /me/history` | latest 40 matches with stake, prize and coin change |

A staked room stores `level`, `stake`, `fee`, `prize` and (poker) `multiplier`;
the running match carries them in `state.bet`. `wallet_tx` records every coin
or gem movement (`buy_in`, `prize`, `daily_bonus`, `cue:<id>`) with the balance
it left. `php bin/migrate.php` adds the new columns to an existing database.
