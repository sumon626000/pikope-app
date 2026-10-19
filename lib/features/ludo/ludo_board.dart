import 'dart:ui';

import 'package:flutter/material.dart';

import '../../game/ludo/ludo_rules.dart';

/// Geometry of a 15x15 Ludo board: the 52-cell ring, the four home columns,
/// the yards and the centre goal. Coordinates are grid cells (0..14); a token
/// is painted at the centre of its cell.
class LudoBoard {
  static const n = 15;

  /// The 52 ring cells, clockwise. Index 0 is colour 0's start square.
  static const path = <List<int>>[
    [6, 13], [6, 12], [6, 11], [6, 10], [6, 9], // 0-4  bottom arm, left col
    [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8], // 5-10 left arm, lower row
    [0, 7], // 11 left tip
    [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], // 12-17 left arm, upper row
    [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0], // 18-23 top arm, left col
    [7, 0], // 24 top tip
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], // 25-30 top arm, right col
    [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6], // 31-36 right arm, upper row
    [14, 7], // 37 right tip
    [14, 8], [13, 8], [12, 8], [11, 8], [10, 8], [9, 8], // 38-43 right arm, lower row
    [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14], // 44-49 bottom arm, right col
    [7, 14], // 50 bottom tip
    [6, 14], // 51
  ];

  /// Home column cells (5) per colour, from the ring toward the centre.
  static const homeColumn = <List<List<int>>>[
    [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9]], // 0 bottom
    [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7]], // 1 left
    [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5]], // 2 top
    [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7]], // 3 right
  ];

  /// Where a finished token rests in the centre (one spot per colour), as
  /// grid-unit centres (0..15).
  static const goal = <List<double>>[
    [7.5, 8.6], // bottom (yellow)
    [6.4, 7.5], // left (blue)
    [7.5, 6.4], // top (red)
    [8.6, 7.5], // right (green)
  ];

  /// The four token spots in each colour's yard, as grid-unit centres (0..15).
  static const yard = <List<List<double>>>[
    [[2.0, 11.0], [4.0, 11.0], [2.0, 13.0], [4.0, 13.0]], // 0 bottom-left
    [[2.0, 2.0], [4.0, 2.0], [2.0, 4.0], [4.0, 4.0]], // 1 top-left
    [[11.0, 2.0], [13.0, 2.0], [11.0, 4.0], [13.0, 4.0]], // 2 top-right
    [[11.0, 11.0], [13.0, 11.0], [11.0, 13.0], [13.0, 13.0]], // 3 bottom-right
  ];

  /// The 6x6 yard rectangle (col,row,size) per colour.
  static const yardRect = <List<int>>[
    [0, 9, 6], // bottom-left
    [0, 0, 6], // top-left
    [9, 0, 6], // top-right
    [9, 9, 6], // bottom-right
  ];

  // Positions (by index): 0 bottom-left, 1 top-left, 2 top-right, 3 bottom-right.
  // Matches the classic Ludo King layout: yellow BL, blue TL, red TR, green BR.
  static const colours = <Color>[
    Color(0xFFF4C20D), // 0 yellow  (bottom-left)
    Color(0xFF1E7BE0), // 1 blue    (top-left)
    Color(0xFFE33124), // 2 red     (top-right)
    Color(0xFF1FA82C), // 3 green   (bottom-right)
  ];

  /// Grid-unit centre (0..15) a token of [colour] sits at for [step].
  static List<double> cellOf(int colour, int step, int tokenSlot) {
    if (step == -1) return yard[colour][tokenSlot];
    if (step <= 50) {
      final cell = path[(LudoRules.start[colour] + step) % LudoRules.ring];
      return [cell[0] + 0.5, cell[1] + 0.5];
    }
    if (step <= 55) {
      final cell = homeColumn[colour][step - 51];
      return [cell[0] + 0.5, cell[1] + 0.5];
    }
    return goal[colour];
  }

  /// Ring cells that are safe (start squares + stars).
  static bool isSafe(int ringIndex) => LudoRules.safeCells.contains(ringIndex);
}

/// Cloth behind a Ludo match. Free boards cost 0.
class LudoBoardTheme {
  const LudoBoardTheme(this.id, this.name, this.price, {required this.field, required this.track, required this.grid});

  final String id;
  final String name;
  final int price;
  final Color field;
  final Color track;
  final Color grid;
}

const ludoBoardThemes = [
  LudoBoardTheme('classic', 'CLASSIC', 0, field: Color(0xFF1B6B3A), track: Color(0xFFFFF8EE), grid: Color(0xFF6F7888)),
  LudoBoardTheme('royal', 'ROYAL', 5000, field: Color(0xFF14284A), track: Color(0xFFFFF3D0), grid: Color(0xFFD4AF37)),
  LudoBoardTheme('sunset', 'SUNSET', 8000, field: Color(0xFF8C2F2A), track: Color(0xFFFFE4C8), grid: Color(0xFF5A2418)),
  LudoBoardTheme('midnight', 'MIDNIGHT', 12000, field: Color(0xFF12141C), track: Color(0xFF2A3142), grid: Color(0xFF3CF0D8)),
  LudoBoardTheme('candy', 'CANDY', 15000, field: Color(0xFF6A2A78), track: Color(0xFFFFF0FA), grid: Color(0xFFE85CAD)),
];

LudoBoardTheme ludoThemeOf(String id) => ludoBoardThemes.firstWhere((t) => t.id == id, orElse: () => ludoBoardThemes.first);
