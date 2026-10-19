import 'dart:ui';

/// Colour scheme of a vector-drawn table.
class TableStyle {
  const TableStyle({
    required this.cloth,
    required this.clothDark,
    required this.rail,
    required this.railDark,
    required this.metal,
    required this.metalDark,
    this.sight = const Color(0xFFF3E9D2),
  });

  final Color cloth;
  final Color clothDark;
  final Color rail;
  final Color railDark;
  final Color metal;
  final Color metalDark;
  final Color sight;
}

/// A table look: either drawn in code ([style]) or a supplied image ([asset]).
class TableSkin {
  const TableSkin(this.id, this.name, {this.asset, this.style})
      : assert(asset != null || style != null);
  final String id;
  final String name;
  final String? asset;
  final TableStyle? style;
}

/// Bundled demo content used while the app runs without a backend.
class DemoData {
  static const _gold = Color(0xFFD9B45A);
  static const _goldDark = Color(0xFF8A6A22);

  static const tableSkins = [
    // Vector tables. "Club Teal" follows the client's gameplay mockup.
    TableSkin('pro_teal', 'Club Teal',
        style: TableStyle(
            cloth: Color(0xFF14A7BC), clothDark: Color(0xFF086E86),
            rail: Color(0xFF8A4A22), railDark: Color(0xFF4A2410),
            metal: _gold, metalDark: _goldDark)),
    TableSkin('pro_green', 'Classic Green',
        style: TableStyle(
            cloth: Color(0xFF1F9150), clothDark: Color(0xFF0C5A2E),
            rail: Color(0xFF6E2F18), railDark: Color(0xFF38150A),
            metal: _gold, metalDark: _goldDark)),
    TableSkin('pro_blue', 'Tournament Blue',
        style: TableStyle(
            cloth: Color(0xFF2F74DC), clothDark: Color(0xFF123C8C),
            rail: Color(0xFF2A2C34), railDark: Color(0xFF0E0F13),
            metal: Color(0xFFC9CED6), metalDark: Color(0xFF6C727C),
            sight: Color(0xFFFFFFFF))),
    TableSkin('pro_red', 'Casino Red',
        style: TableStyle(
            cloth: Color(0xFFB3202F), clothDark: Color(0xFF6A0E19),
            rail: Color(0xFF3B2416), railDark: Color(0xFF1A0E07),
            metal: _gold, metalDark: _goldDark)),
    TableSkin('pro_black', 'Midnight Gold',
        style: TableStyle(
            cloth: Color(0xFF454B5A), clothDark: Color(0xFF1F222B),
            rail: Color(0xFF17181D), railDark: Color(0xFF050506),
            metal: _gold, metalDark: _goldDark,
            sight: Color(0xFFE9C56B))),
    // Client-supplied artwork (600x351 images).
    TableSkin('table2', 'Royal Blue', asset: 'assets/images/tables/table2.png'),
    TableSkin('table1', 'Seriouz', asset: 'assets/images/tables/table1.png'),
    TableSkin('table3', 'Pharaoh', asset: 'assets/images/tables/table3.png'),
    TableSkin('table4', 'Night Star', asset: 'assets/images/tables/table4.png'),
    TableSkin('table5', 'Crimson', asset: 'assets/images/tables/table5.png'),
    TableSkin('table6', 'Silver Crest', asset: 'assets/images/tables/table6.png'),
    TableSkin('table8', 'Ember Knot', asset: 'assets/images/tables/table8.png'),
  ];

  static TableSkin skin(String id) =>
      tableSkins.firstWhere((s) => s.id == id, orElse: () => tableSkins.first);

  static const avatars = [
    'asset:avatar_1',
    'asset:avatar_2',
    'asset:avatar_3',
    'asset:avatar_4',
    'asset:avatar_5',
    'asset:avatar_6',
  ];

  static const botNames = ['ENEMY 1', 'ENEMY 2', 'ENEMY 3'];
  static const botAvatars = ['asset:avatar_2', 'asset:avatar_3', 'asset:avatar_4'];

  static const leaderboard = [
    (name: 'CueMaster', avatar: 'asset:avatar_3', wins: 148, coins: 61200),
    (name: 'RiverKing', avatar: 'asset:avatar_5', wins: 131, coins: 48750),
    (name: 'AceBreaker', avatar: 'asset:avatar_2', wins: 117, coins: 40100),
    (name: 'PocketQueen', avatar: 'asset:avatar_6', wins: 96, coins: 33900),
    (name: 'SideSpin', avatar: 'asset:avatar_4', wins: 74, coins: 21400),
    (name: 'Rail Runner', avatar: 'asset:avatar_2', wins: 58, coins: 15250),
    (name: 'Bluff Shot', avatar: 'asset:avatar_5', wins: 41, coins: 9800),
  ];
}
