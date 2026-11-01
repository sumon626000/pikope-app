# Design system mapping (Phase 2)

Import for new code: `package:billiard_poker/core/design/design.dart`

## Colors

| Token (`DesignColors`) | Legacy alias |
|------------------------|--------------|
| `ink` … `dim`, `betLevels` | `DuelColors.*` |
| `appBackground` … `cardBack` | `AppColors.*` |

## Typography

| Token | Legacy |
|-------|--------|
| `DesignTypography.label()` | `AppText.label()` |
| `displayFont`, `cardFont` | `AppText.display`, `AppText.card` |

## Layout & spacing

| Token | Used by |
|-------|---------|
| `DesignLayout.canvasSize` | `DuelCanvas.size` |
| `DesignLayout.primaryButton*` | `DuelButton` defaults |
| `DesignLayout.gameCard*` | `GameCard` in `duel_home_screen.dart` |
| `DesignLayout.navTile*` | `NavTile` |
| `DesignSpacing.*`, `DesignRadii.*` | Phase 3+ migrations |

## Reference components

| Widget | Wraps |
|--------|--------|
| `DesignPrimaryButton` | `DuelButton` (lobby primary) |
| `DesignCompactButton` | `DuelButton` (dialogs) |
| `DesignGameCardFrame` | SizedBox footprint only |
| `DesignNavTileSlot` | SizedBox footprint only |

## Breakpoints

`DesignBreakpoints.phoneLike`, `tabletOrWider`, `desktopWide`, `isLandscape` — use in Phase 3/7.

## Unchanged in Phase 2

- `duelPanel`, `showDuelDialog`, `GameButton`, `NavTile`, `GameCard` implementations
- All screen layouts
