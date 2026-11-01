# Phase 7 — Responsive testing report

Date: 2026-11-02

## Scope

Automated **L3** layout checks at five landscape viewports (from `ROADMAP.md`):

| Viewport | Typical use |
|---------:|-------------|
| 640×360 | Small phone landscape |
| 800×360 | Common phone landscape |
| 915×412 | Large phone (e.g. Samsung S908E class) |
| 1280×800 | Tablet / small desktop |
| 1920×1080 | Full HD browser |

**Surfaces under test** (`test/ui_landscape_responsive_test.dart`):

- `DuelHomeScreen`
- `LoadingSplashBody` (static splash extracted from `LoadingScreen`)
- `LoginScreen`
- `PoolHubScreen`
- `HowToPlayScreen`

Each case pumps one frame and asserts `tester.takeException()` is null (catches RenderFlex overflow and layout errors).

## Fixes applied this phase

1. **Login** — Removed fixed 1600×900 `FittedBox` wrapper; brand column uses `FittedBox(scaleDown)`; form column uses `SingleChildScrollView` to avoid bottom overflow on short viewports.
2. **Loading** — Extracted `LoadingSplashBody` for testability; full `LoadingScreen` still runs timers/navigation (not pumped in L3 suite).
3. **Legacy widget test** — `HomeScreen` integration test skipped (`skip: true`); coverage moved to `DuelHomeScreen` in L3 file.

## Results

| Suite | Result |
|-------|--------|
| `flutter test test/ui_landscape_responsive_test.dart` | **25/25 passed** |
| `flutter test` (full) | **133 passed**, 1 skipped (legacy home), 0 failed |
| `flutter analyze lib` | **No issues** (after login brace fix) |

## NOT verified (this phase)

| Level | Item |
|-------|------|
| L4 | Device smoke on SM S908E after Phase 7 login/loading changes |
| L5 | `flutter run -d chrome` manual pass on all routes |
| L6 | `flutter build web` / release APK |
| L3 | Gameplay screens (Pool/Ludo/Carrom), shop, settings, dialogs, bet/matchmaking |
| L3 | `LoadingScreen` full widget (timers); splash layout covered via `LoadingSplashBody` |
| L3 | `AppStartGate`, `MandatoryUpdateScreen`, incoming-challenge banner |

## Recommended follow-ups (Phase 8)

- Extend L3 matrix to high-traffic secondary routes and one dialog each.
- Device + Chrome spot-check after any layout change.
- Production builds and final regression checklist per `ui-overhaul.mdc`.
