import 'package:flutter/material.dart';

/// Single source of truth for color tokens. [DuelColors] and [AppColors]
/// alias these values — do not add new colors outside this file during the overhaul.
abstract final class DesignColors {
  // --- Lobby / Duel hall (DuelCanvas screens) ---
  static const ink = Color(0xFF070A18);
  static const navy = Color(0xFF0E1433);
  static const glass = Color(0xE6101426);
  static const rim = Color(0xFF2B3566);
  static const rimLight = Color(0xFF4A5AA8);
  static const duelGreen = Color(0xFF3ED12F);
  static const duelPurple = Color(0xFF7B4DFF);
  static const duelBlue = Color(0xFF2F6BFF);
  static const duelGold = Color(0xFFFFC93C);
  static const duelRed = Color(0xFFFF3B4E);
  static const silver = Color(0xFFE9ECF5);
  static const dim = Color(0xFF8E96B8);

  static const betLevels = [
    Color(0xFF35D05A),
    Color(0xFFFF4055),
    Color(0xFF3B6CFF),
    Color(0xFFE8D23A),
    Color(0xFFB04DFF),
  ];

  // --- In-game / PageFrame / settings (Pool City purple since 2026-11) ---
  static const appBackground = Color(0xFF261C49);
  static const appBackgroundAlt = Color(0xFF2A1C5E);
  static const appPanel = Color(0xFF2E2564);
  static const appFrame = Color(0xFF6E5BD6);
  static const appFrameLight = Color(0xFF8C7CE8);
  static const appActive = Color(0xFF2EE84F);
  static const appGold = Color(0xFFFFC928);
  static const appDanger = Color(0xFFFF4D4D);
  static const appText = Color(0xFFF2F2F5);
  static const appTextDim = Color(0xFF9A9AA8);
  static const cardBack = Color(0xFFD9263E);

  static const ludoAccent = Color(0xFFE8721C);
  static const carromAccent = Color(0xFFD9A34A);
  static const poolEightAccent = Color(0xFF2E8B57);

  static const dialogOverlayScrim = Color(0xB3000000);

  // --- Pool City theme (portrait home + gameplay restyle, 2026-11) ---
  // Values sampled from the reference app's screenshots.
  static const pcInk = Color(0xFF1B0E3D); // page top
  static const pcPlum = Color(0xFF24072D);
  static const pcMagenta = Color(0xFF5C193D); // mid-page glow
  static const pcViolet = Color(0xFF66285F);
  static const pcNavyLow = Color(0xFF122850); // blurred table in the lower half
  static const pcNavyBottom = Color(0xFF0C1632);
  static const pcTableBlue = Color(0xFF3B79B4);
  static const pcTableCyan = Color(0xFF78D8FE);

  static const pcGameBg = Color(0xFF261C49); // match screens
  static const pcPanel = Color(0xFF442F85); // glass panel / list row
  static const pcPanelDeep = Color(0xFF2E2564); // dialog body
  static const pcPanelLight = Color(0xFF5A35C1);
  static const pcPanelLighter = Color(0xFF6D50C4);
  static const pcPanelRim = Color(0xFF7D6AD6);
  static const pcHeaderBar = Color(0xFF443196);
  static const pcSeason = Color(0xFF47339B);
  static const pcSeasonDeep = Color(0xFF382F84);

  static const pcPill = Color(0xFF170E29);
  static const pcPlus = Color(0xFF2BB04A);
  static const pcPlusLight = Color(0xFF4ED86A);
  static const pcGold = Color(0xFFF5B942);
  static const pcGoldDeep = Color(0xFFDA9B14);
  static const pcCash = Color(0xFF3FC95B);

  static const pcRibbon = Color(0xFFDB308A);
  static const pcRibbonDeep = Color(0xFFC21773);
  static const pcRibbonEdge = Color(0xFF850549);

  static const pcTileOrange = Color(0xFFF4A52A);
  static const pcTileOrangeDeep = Color(0xFFC96A12);
  static const pcTilePink = Color(0xFFF04A95);
  static const pcTilePinkDeep = Color(0xFFB81C6C);
  static const pcTileTeal = Color(0xFF22C4E0);
  static const pcTileTealDeep = Color(0xFF0B64A2);
  static const pcTileBlue = Color(0xFF3F7BE3);
  static const pcTileBlueDeep = Color(0xFF1F3FAE);
  static const pcTileGreen = Color(0xFF2AA790);
  static const pcTileGreenDeep = Color(0xFF1C6A6E);

  static const pcNav = Color(0xFF312269);
  static const pcNavRim = Color(0xFF4A3A8A);
  static const pcNavActive = Color(0xFF4C63D8);
  static const pcNavActiveDeep = Color(0xFF373F84);
  static const pcNavText = Color(0xFFA7ABDC);

  static const pcBlueButton = Color(0xFF2F7BFF);
  static const pcBlueButtonDeep = Color(0xFF1B4FD0);
  static const pcRedButton = Color(0xFFE23B5A);
  static const pcText = Color(0xFFFFFFFF);
  static const pcTextDim = Color(0xFFBFB7E8);
}
