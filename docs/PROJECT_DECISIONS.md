# Decisions

## Rule gaps - please confirm with the client

The rules PDF does not cover these. Each is implemented in
`lib/game/rules/rules_engine.dart` (and tested), and is easy to change.

| # | Gap | Decision | Why |
|---|---|---|---|
| 1 | Several players can need the same ball (A-spades and A-hearts are both ball 1). What happens once it is pocketed? | **Every pocketed object ball is re-spotted** (foot spot, or nearest free point on the long string) after the shot. All 15 balls are always in play. | Otherwise other players - and anyone who later draws that rank as a penalty - could never finish. |
| 2 | Cue ball pocketed (scratch) | Foul: turn ends, nothing pocketed counts, next player has ball in hand. **No penalty card.** | The PDF lists exactly three card penalties; a scratch is not one of them. |
| 3 | Cue ball hits nothing | Treated as wrong first contact: +1 card, turn ends. | "The first ball contacted must match the revealed card" is not met. |
| 4 | Break shot | Open shot: no card to reveal, no wrong-ball penalty. Own balls pocketed count; free balls give the extra shot. | Nobody can call a ball in a full rack. |
| 5 | How to play balls 14/15 when first contact must match a card | A player may **nominate 14 or 15 as the target without a card**. | They "are Free Shot Balls for all players". |
| 6 | Both fouls in one shot | The heavier applies (+2), not the sum. | Simplest reading. |
| 7 | Penalty card of a rank the player already completed | The objective **re-opens**: that ball must be pocketed again. | "Penalty cards become new objectives". |
| 8 | Own ball pocketed that was not the revealed one (legal first contact) | Counts as completed. | It is "represented by your cards", so no penalty; refusing it would be odd. |
| 9 | Extra shot | Banked: when a legal shot pockets nothing of yours, one banked extra shot keeps the turn alive. Lost on a foul. | "+1 extra shot". |
| 10 | Which card grays | The revealed card if it matches the pocketed ball, else random among equivalents. | PDF: "random". |
| 11 | Timeout while able to declare | +1 card, so the player is no longer finished. | Timeout rule applies to every turn. |
| 12 | Penalty pile | The 24 undealt cards. If it runs out, the turn still ends but no card is given. | Keeps "no duplicate exact card" true. |
| 13 | Shot clock | 30 s default (20/30/45/60 selectable). | Not specified. |
| 14 | Turn order vs "clockwise" | Break-draw order **is** the turn order; seats are laid out clockwise in that order around each viewer. | Satisfies both sentences of the PDF. |

## 8-Ball, 9-Ball, 10-Ball - gaps in "Rules of Billiards"

Implemented in `lib/game/pool/pool_rules.dart`.

| # | Gap | Decision |
|---|---|---|
| P1 | 8-Ball says the player pockets a "called"/"intended" ball, but only the 8 is given a call procedure | Only the 8-ball needs a call (tap a pocket). Ordinary balls are not called. |
| P2 | 8-ball pocketed on the break | Spotted back; play continues by the normal break rule. |
| P3 | Hitting the 8 first on an open table | Foul (the 8 is nobody's ball until a group is cleared). |
| P4 | Both a solid and a stripe pocketed on the shot that decides the groups | The first one to drop decides. |
| P5 | Who breaks | Random ("the system determines"). |
| P6 | Shot clock (not mentioned for these games) | Same clock as Billiard Poker; running out is a foul, opponent gets ball in hand. In 9-Ball it counts toward three fouls. |
| P7 | Illegal 9-Ball break (nothing pocketed, fewer than 4 balls to a rail) | Foul: incoming player has ball in hand. |
| P8 | Balls pocketed during a 9-Ball push out | Stay down, except the 9 which is spotted. Bots never push out and always take the shot when offered. |
| P9 | "Ball knocked off the table" / "touching a ball" fouls | Cannot happen in this simulation; not implemented. |
| P10 | 10-Ball: call-shot is not in the document | Not implemented; any legally pocketed ball keeps the turn. |
| P11 | Pass & play in 1 v 1 | Nothing is hidden, so no hand-off screen; the table view turns to the shooter. |

## Engineering

- **Pure-Dart game core** (`lib/game/`): no Flutter imports, all randomness
  injected. The same `RulesEngine` can run server-side for authority.
- **Custom physics** instead of a physics package: fixed 1/300 s step,
  deterministic, cloneable. Determinism lets bots test-run shots and will let
  online clients replay a shot from (angle, power, spin).
- **Logical coordinates**: 1000x500 playfield; UI is a 1600x900 design canvas
  scaled to fit, so nothing clips or overlaps on any landscape phone/tablet.
- **POV**: the viewer is always the bottom seat. Seats rotate clockwise in turn
  order; the table view is turned 180 degrees for the two players on the far
  side. A true 90-degree turn would stand the table upright on a landscape
  screen, so side seats use the nearest of the two orientations.
- **State**: Riverpod for app state (profile, settings, services); one
  `GameController` per match with separate notifiers for HUD, frame and clock
  so the table repaints without rebuilding widgets.
- **Demo backend**: profile in `SharedPreferences` behind `AppStorage`; bots
  stand in for remote players. No fake "online" - the Online button says so.
- **Card ink is black for every suit**, as the final card spec states.

## Lobby and economy (requirements doc "Developers Specs Billiard", 2026-10-06)

Built from the Google Doc and its nine mockups. Where the doc was silent or
contradicted itself, these choices were made - please confirm or correct:

- **Two staked modes.** BILLIARD (1v1; the server draws 8-, 9- or 10-ball when
  the match starts) and BILLIARD POKER (4 players). Bet levels follow the
  mockups: stake 20 / 100 / 500 / 2,000 / 5,000 plus a 5% house fee, i.e.
  buy-in 21 / 105 / 525 / 2,100 / 5,250. Billiard pays 2 x stake (40 ... 10K).
- **Billiard Poker prize = stake x jackpot multiplier**, drawn by the server
  with the doc's table (x3 47.86% ... x10,000 0.00001%) and shown on the wheel
  at the start of the match. The doc also says "the winner gets x4 of buy-in";
  the table was taken as the rule. **Note for the operator:** with this table
  the average prize is about 6.26 x stake while the four players together put
  in 4 x stake (+ fees), so the house pays out more than it collects on
  average (the x100 slice at 2.35% is what does it). All of it - fee, stakes,
  jackpot odds - is editable on the admin page without a new build.
- **Buy-in is taken when the match starts**, not while waiting; the winner is
  paid when it ends; a player who leaves or times out forfeits. Every movement
  is in the `wallet_tx` ledger.
- **Coins are no longer handed out for playing.** Practice against bots and
  friendly private rooms move no coins (experience only); the daily bonus
  ladder (200 ... 1,500 coins, 5 gems on day 7) is the free source. New
  players start with 2,000 coins.
- **Buying coins/gems with real money is not wired up** ("tbd" in the doc):
  the shop lists packs marked COMING SOON.
- **Cues are looks only** (8 cues, coins or gems): the server decides the
  physics, so a cue cannot change how a shot plays. Opponents see your cue.
- **Nickname:** 3-16 letters, digits or "_" (the doc says alphanumeric; the
  mockup shows underscores).
- **Gems** (the purple chip of the mockups) are the second currency; they come
  from the daily bonus today and buy the two special cues.
- **Mission, Club, Mail, Notifications** open an explanatory message only;
  **Friends** opens the free private-room flow. Level and rank are computed
  from experience and online wins.
- Not built from the "additional requirements" list: spectator mode,
  tournaments, multi-language, in-app purchases, streaming, iOS/web builds.

## Ludo (added 2026-10-13)

A third game, per the client's request. Classic Ludo King-style board and rules.
Shares the lobby, wallet and bet ladder with the pool games.

- **Modes:** LUDO 2-player (opposite colours) and 4-player (all four colours).
  Practice is free (vs bots); "Play for coins" uses the same bet levels as
  Billiard, winner takes the pot (2x stake for 2 players, 4x for 4), no wheel.
- **Colour choice:** in practice the player picks their colour; in online
  quick-match the server assigns colours by seat (you at the bottom).
- **Rules:** need a 6 to leave base and to roll again; capture (landing on a
  non-safe cell with an opponent) sends it home and grants another roll;
  finishing a token grants another roll; three 6s forfeit the turn; home is
  reached only by an exact roll; safe cells are the 4 colour starts + 4 stars;
  first to get all four tokens home wins the pot. A timed-out player is auto-
  played and, after 3 misses, drops out (the last one standing wins).
- **Server-authoritative:** the server rolls every die and applies every move
  (`backend/src/Game/LudoEngine.php`), a mirror of `lib/game/ludo/ludo_rules.dart`.
- **Not implemented (please confirm):** blockades (two tokens of a colour
  forming a wall that others cannot pass) are omitted to keep the first
  version simple; let us know if the client wants them.
- Game keys in the backend are `ludo2` / `ludo4`; the engine kind is `ludo`.

## Challenge (1v1 invites, added 2026-10-13)

A "CHALLENGE" tile on the home screen (replacing the CLUB placeholder).

- **Who:** everyone online now (used a token in the last 3 minutes), except
  yourself; a player already in a match shows "IN MATCH" and cannot be
  challenged. (`GET /challenge/online`.)
- **Send:** pick the game (BILLIARD or LUDO) and a stake (FREE or a bet level),
  send it (`POST /challenge/send`). The invite lives 60 seconds. You must not
  be in a match and must afford the buy-in.
- **Receive:** the target gets a pop-up anywhere in the lobby (the home screen
  and the Challenge screen poll `GET /challenge/inbox` every 3 s) and can
  ACCEPT or DECLINE.
- **Accept:** both buy-ins are taken and a private 1v1 match starts
  (`POST /challenge/{id}/accept` → a room with its gameId); the sender's screen
  polls its outgoing invite, sees it accepted and opens the same match.
- Backed by a `challenges` table; expired/old invites are cleaned by the cron.

## Admin tools + in-app notices (added 2026-10-13)

The admin page (`/admin`, HTTP Basic) gained four tools the client asked for,
all CSRF-protected and escaped:
- **Adjust a balance:** give or take coins/gems from a player with a reason
  (logged in `wallet_tx`, never below zero). On the main page and per player.
- **Player detail** (`/admin/player?id=X`): profile + last 40 wallet movements
  + last 40 match results; linked from the players table.
- **Notices & banners:** post an announcement (`news` for the inbox, `banner`
  for a highlighted one) with an optional expiry, and deactivate old ones.
  The app shows active notices via the mail icon -> INBOX (`GET /notices`).
- **Live now:** players online (last 3 min) and the running matches with their
  players.

Friends (private room) now also offers **LUDO (2 / 4 players)** for free
play with a shareable code, alongside the pool games.

## Carrom (added 2026-10-16)

A fourth game, per the client's request: "like Carrom Pool", with the board
drawn from the Carrom Pool reference (light wood field, dark frame with orange
corners, black corner pockets, double-lined base lanes with orange-filled
circles, thin centre circle; cream/black pieces with concentric rings, red
queen, red striker with a white star).

- **Mode:** 1 v 1 only ("disc pool" rules). Practice is free (vs a bot);
  "Play for coins" uses the Billiard bet ladder, winner takes the pot (2x
  stake). Friends offers a free private CARROM room; Challenge offers CARROM.
- **Rules:** seat 0 plays white (discs 1-9), seat 1 black (10-18), disc 19 is
  the queen. Pocket your own piece: shoot again. Pocket an opponent's piece:
  it counts for them, turn passes. The queen must be covered by one of your
  pieces in the same or the very next stroke, else she returns to the centre.
  Your last piece may not drop while the queen is unowned (it returns). Striker
  pocketed = foul: everything that dropped returns, plus one piece you had
  already pocketed. First to pocket all nine wins. Shot clock as in pool; three
  timeouts in a row and the player is out.
- **Controls:** slide the striker along the base line with the bar under the
  board (or tap it), then drag anywhere on the board to pull the striker back
  (slingshot) and release. Seat 1 sees the board turned half a turn so its own
  base line is at the bottom.
- **Physics:** `lib/game/carrom/carrom_physics.dart` mirrored exactly by
  `backend/src/Game/CarromPhysics.php` (1000x1000 field, striker r=37 mass
  2.4, pieces r=27 mass 1, corner capture radius 50). `test/carrom_test.dart`
  runs the same strokes through both and requires identical rest positions.
- **Server-authoritative** like pool: the client sends `{x, dirX, dirY,
  power}`, the server places the striker (nudged clear of pieces), simulates,
  rules (`CarromEngine.php`, a mirror of `carrom_rules.dart`) and stores the
  discs; the other client replays the stroke from the same numbers.
- **Bots:** server stand-ins (`Bots::carrom`) and the practice bot
  (`carrom_bot.dart`) use the same plan: ghost-disc aims at every own piece
  (and the queen) for every pocket from seven striker positions, the 12 most
  promising test-run on a copy of the board.
- Game key `carrom`; engine kind `carrom`.
- **Looks are per player, purely cosmetic:** the lobby lets you pick a
  striker (8), a piece set (5) and a board (6: classic light wood, walnut,
  royal blue, emerald, cherry, midnight neon), saved in settings
  (`carromStriker` / `carromPieces` / `carromBoard`) and drawn by
  `carrom_skins.dart` + `CarromBoardPainter`. Physics and the server never
  see them; your opponent sees their own choices.

## Home: every game billed the same (2026-10-16)

The client asked that pool stop being "the main game": the home shows three
equal cards, POOL, LUDO and CARROM, and nothing pool-specific sits outside
them. `PoolHubScreen` holds all of pool: 8-, 9- and 10-ball tables (now
staked queues of their own: `DuelMode.eight/nine/ten`, server games
`eight/nine/ten` accept a bet level), Billiard Poker with its jackpot banner,
the random "quick duel" (`billiard`), pool practice and the cue shop. The
home's PRACTICE and PLAY WITH FRIENDS banners open a POOL / LUDO / CARROM
chooser first. The nav row lost CUES (in the pool hub) and gained DATA.

## Dialogs are drawn on the canvas (2026-10-16)

`showDuelDialog` fits every dialog into the page canvas shrunk 1.65x (so dialogs
read 1.65x larger than page widgets of the same width). Plain `showDialog` laid them out in the phone's own logical pixels, so
on short screens the content overflowed the dialog box and the buttons at
the bottom were painted outside it and could not be tapped (the client's
"challenge ACCEPT / DECLINE do nothing").

## Coins: what keeps them honest

- The app never writes a balance. Every coin movement is `Economy::move` on
  the server, inside a transaction with the row locked, and it writes a
  `wallet_tx` ledger row (welcome grant, buy-in, prize, daily bonus, cue
  purchase, admin adjustments). Practice results (`/matches/bot`) pay no
  coins, only a little XP.
- Buy-ins are taken when the match starts and prizes paid from the server's
  own result; shots are simulated on the server, so a tampered client cannot
  claim a win.
- Tokens are 32 random bytes stored hashed; the admin page is basic-auth with
  a rate limit and CSRF tokens; coin-moving endpoints are throttled per player
  (`Api::throttled`).
- `bin/audit-wallets.php` checks every balance against the ledger (`--fix`
  rewrites a bad balance from the ledger); the admin dashboard shows the
  mismatch count.
