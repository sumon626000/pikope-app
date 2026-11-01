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

  // --- In-game / PageFrame / settings ---
  static const appBackground = Color(0xFF1E1E21);
  static const appBackgroundAlt = Color(0xFF26262A);
  static const appPanel = Color(0xFF15151A);
  static const appFrame = Color(0xFF4A4973);
  static const appFrameLight = Color(0xFF6C6BA0);
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
}
