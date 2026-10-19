# Design mapping

Reference: the dark-layout mockups in the rules PDF (1600x900 / 1672x941).
The game screen is built on a fixed 1600x900 canvas at the same coordinates.

| Mockup element | Implementation | File |
|---|---|---|
| Dark slate room with slab seams | `RoomBackground` | `core/widgets.dart` |
| Coin tile top-left ("2000") | `CoinsTile`, art cropped from the mockup | `core/widgets.dart` |
| Vertical cue power bar, left | `PowerBar` - drag down, release to shoot | `game/widgets/hud.dart` |
| MENU tile bottom-left | `MenuTile` -> pause overlay | `hud.dart`, `overlays.dart` |
| Cue-ball spin selector top-right | `SpinControl` (red dot = tip position) | `hud.dart` |
| Table centre (860 px wide) | `TableView`: supplied table image + live balls, cue, aim guide | `game/widgets/table_view.dart` |
| 4 avatars: bottom-left, left, top-right, right | `SeatView` at the mockup coordinates | `hud.dart` (`SeatLayout`) |
| Green ring on the active player | Ring drains with the shot clock, turns red under 10 s | `hud.dart` |
| Break: 3x10 face-down spread on the cloth | `buildBreakSpread` | `hud.dart` |
| Break: one card beside each avatar | `buildBreakCards`, flips face-up, 1ST-4TH badges | `hud.dart` |
| Opponent hands: red backs, top row / side stacks | `buildHand` + `CardBack` | `hud.dart`, `card_view.dart` |
| Completed card shown gray | `completed` state on face and back | `card_view.dart` |
| Shown card raised by half | `raisedCards` -> half-height offset toward the table | `hud.dart` |
| Final card face | `CardFace`: white, black ink, small rank + suit top-left, big rank bottom-right | `card_view.dart` |
| Aim line, ghost ball, cue stick | `_TablePainter` | `table_view.dart` |

## Layout revision (client request)

After seeing the first build the client asked for a much larger table and
larger, clearer balls and cue, in the style of the classic mobile pool games
(reference screenshots supplied in chat). The match screens therefore moved off
the mockup's 1600x900 coordinates to a 1950x900 canvas (`SeatLayout`,
`DesignCanvas.tableSize`):

- Billiard Poker: table 1180 wide (was 860); opponents' hands are compact card
  backs in the margins, the viewer's hand and objective panel sit under the table.
- 8/9/10-Ball: table 1272 wide under a player bar (names, avatars, ball trays).
- Ball radius 16 (was 14) on the 1000-unit playfield, glossy sprites, thicker
  cue and an outlined aim line.

## Added (not in the mockups, required by the brief)

- Status line (whose turn, what to do) top-left of the table.
- Objective panel bottom-right: unique balls (not cards), done ticks, penalty
  rings, and the two free-ball selectors.
- Banners for fouls, extra shot, ready-to-declare; DECLARE WINNER button;
  winner panel with stats; pass-the-device screen.
- Home, match setup, profile/settings, leaderboard, how-to-play screens in the
  same visual language.

## Differences from the mockups

- **Card faces**: the play mockups show coloured cards; the PDF's last page
  ("Card design final") says white with black ink - that one is implemented.
- **Table art**: the mockup's teal/wood/gold table is not among the supplied
  files, so it is drawn in code (`game/widgets/table_art.dart`, default skin
  "Club Teal") - vector, sharp at any resolution - along with four more
  colour schemes. The 7 supplied 600x351 images in `design_reference/` stay
  selectable in Profile & Tables.
- **Typeface**: Orbitron (closest free match to the mockup lettering) and
  DM Serif Display on cards.
