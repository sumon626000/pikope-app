# Project analysis

Sources read: `original client docs/Rules Billiard Poker.pdf` (primary, 9 pages
incl. 7 mockup images), `original client docs/Rules of Billiards.pdf`
(secondary, general pool mechanics only), `design_reference/` (7 table images),
`promt` (build brief).

Not readable: the two links in `reference-design-link` ("Pool Table Designs",
"Billiard Poker - Card deal"). They are artifacts owned by another account and
need an interactive access approval, so they were **not** used.

## The game, as specified

| Topic | Rule |
|---|---|
| Players | 4, individual, turns rotate clockwise |
| Break | Each picks one face-down card from a spread 52-card deck; highest breaks. K > Q > ... > 2 > A; ties by suit, spades > hearts > diamonds > clubs. Others follow in descending order. |
| POV | Each player sees the table from the bottom; POV rotates clockwise |
| Deal | 7 cards each; no exact card is held twice |
| Mapping | A=1, 2-10, J=11, Q=12, K=13; suit irrelevant |
| Duplicates | Same rank = one ball (A A A A 7 7 7 -> balls 1 and 7) |
| Show card | After pocketing, one matching card is raised by half and shown to all; random among equivalents |
| Gray out | Exactly one card grays per pocketed ball |
| Free balls | 14 and 15 belong to nobody; pocketing one gives +1 extra shot |
| Turn | Reveal the matching card, cue ball must hit that ball first, keep shooting until miss/foul |
| Wrong first contact | +1 penalty card, turn ends |
| Wrong ball pocketed | +2 penalty cards, turn ends |
| Timeout | +1 penalty card, turn passes |
| Penalty cards | New objectives |
| Winning | After completing everything, wait for the next scheduled turn and declare; whoever declares first wins (race) |
| Card look | White, black ink; small rank + suit top-left, big rank bottom-right |

## The other three games

`Rules of Billiards.pdf` holds full rules for **9-Ball**, **8-Ball Pool** (1 v 1)
and **10-Ball Pool** (1 v 1). They were first treated as reference only (the
build brief says so); the client then confirmed all four games belong in one
app, so each is implemented as its own playable game.

## What the documents leave open

Listed with the chosen answer in [PROJECT_DECISIONS.md](PROJECT_DECISIONS.md):
what happens to pocketed balls that others still need, scratches, the break
shot, hitting no ball, nominating free balls, penalty card of a finished rank.

## Mockups

Seven images in the rules PDF: one early concept (light background, blue
table), three of the final dark layout (break spread, break cards flying to the
players, play with hands), one showing a revealed card raised and gray
completed cards, and the final card face. See [DESIGN_MAPPING.md](DESIGN_MAPPING.md).
