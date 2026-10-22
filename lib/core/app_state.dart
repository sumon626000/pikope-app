import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_storage.dart';
import 'audio_service.dart';
import 'cloudinary_service.dart';

/// Local player's profile and preferences.
class AppSettings {
  const AppSettings({
    this.name = 'PLAYER1',
    this.avatar = 'asset:avatar_1',
    this.coins = 2000,
    this.wins = 0,
    this.games = 0,
    this.soundOn = true,
    this.shotSeconds = 30,
    this.tableSkin = 'pro_teal',
    this.botLevel = 1,
    this.authToken = '',
    this.onboarded = false,
    this.carromStriker = 'classic',
    this.carromPieces = 'classic',
    this.carromBoard = 'classic',
    this.ludoBoard = 'classic',
    this.ownedPoolTables = const ['pro_teal', 'pro_green', 'pro_blue'],
    this.ownedCarromBoards = const ['classic', 'walnut'],
    this.ownedLudoBoards = const ['classic'],
    this.languageCode = 'en',
    this.challengesEnabled = true,
    this.challengePoolEnabled = true,
    this.challengeLudoEnabled = true,
    this.challengeCarromEnabled = true,
  });

  final String name;
  final String avatar;
  final int coins;
  final int wins;
  final int games;
  final bool soundOn;
  final int shotSeconds;
  final String tableSkin;

  /// 0 easy, 1 normal, 2 hard.
  final int botLevel;

  /// Backend session token (empty: not signed in).
  final String authToken;

  /// The player has been through the sign-in screen (as a guest or with an
  /// account), so the app opens straight on the home screen.
  final bool onboarded;

  /// Carrom striker and piece-set skins (see lib/features/carrom/carrom_skins.dart).
  final String carromStriker;
  final String carromPieces;
  final String carromBoard;

  /// Ludo cloth (see ludo board themes).
  final String ludoBoard;

  /// Boards this device has unlocked. Free ones are always included.
  final List<String> ownedPoolTables;
  final List<String> ownedCarromBoards;
  final List<String> ownedLudoBoards;

  /// `en` (default) or `bn` — full app language.
  final String languageCode;

  /// Legacy flag synced with any of [challengePoolEnabled], [challengeLudoEnabled], [challengeCarromEnabled].
  final bool challengesEnabled;

  /// Incoming 1v1 invites per game family (Settings).
  final bool challengePoolEnabled;
  final bool challengeLudoEnabled;
  final bool challengeCarromEnabled;

  double get botSkill => const [0.25, 0.6, 0.92][botLevel.clamp(0, 2)];

  AppSettings copyWith({
    String? name,
    String? avatar,
    int? coins,
    int? wins,
    int? games,
    bool? soundOn,
    int? shotSeconds,
    String? tableSkin,
    int? botLevel,
    String? authToken,
    bool? onboarded,
    String? carromStriker,
    String? carromPieces,
    String? carromBoard,
    String? ludoBoard,
    List<String>? ownedPoolTables,
    List<String>? ownedCarromBoards,
    List<String>? ownedLudoBoards,
    String? languageCode,
    bool? challengesEnabled,
    bool? challengePoolEnabled,
    bool? challengeLudoEnabled,
    bool? challengeCarromEnabled,
  }) =>
      AppSettings(
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        coins: coins ?? this.coins,
        wins: wins ?? this.wins,
        games: games ?? this.games,
        soundOn: soundOn ?? this.soundOn,
        shotSeconds: shotSeconds ?? this.shotSeconds,
        tableSkin: tableSkin ?? this.tableSkin,
        botLevel: botLevel ?? this.botLevel,
        authToken: authToken ?? this.authToken,
        onboarded: onboarded ?? this.onboarded,
        carromStriker: carromStriker ?? this.carromStriker,
        carromPieces: carromPieces ?? this.carromPieces,
        carromBoard: carromBoard ?? this.carromBoard,
        ludoBoard: ludoBoard ?? this.ludoBoard,
        ownedPoolTables: ownedPoolTables ?? this.ownedPoolTables,
        ownedCarromBoards: ownedCarromBoards ?? this.ownedCarromBoards,
        ownedLudoBoards: ownedLudoBoards ?? this.ownedLudoBoards,
        languageCode: languageCode ?? this.languageCode,
        challengesEnabled: challengesEnabled ?? this.challengesEnabled,
        challengePoolEnabled: challengePoolEnabled ?? this.challengePoolEnabled,
        challengeLudoEnabled: challengeLudoEnabled ?? this.challengeLudoEnabled,
        challengeCarromEnabled: challengeCarromEnabled ?? this.challengeCarromEnabled,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      name: j['name'] as String? ?? d.name,
      avatar: j['avatar'] as String? ?? d.avatar,
      coins: j['coins'] as int? ?? d.coins,
      wins: j['wins'] as int? ?? d.wins,
      games: j['games'] as int? ?? d.games,
      soundOn: j['soundOn'] as bool? ?? d.soundOn,
      shotSeconds: j['shotSeconds'] as int? ?? d.shotSeconds,
      tableSkin: j['tableSkin'] as String? ?? d.tableSkin,
      botLevel: j['botLevel'] as int? ?? d.botLevel,
      authToken: j['authToken'] as String? ?? d.authToken,
      onboarded: j['onboarded'] as bool? ?? d.onboarded,
      carromStriker: j['carromStriker'] as String? ?? d.carromStriker,
      carromPieces: j['carromPieces'] as String? ?? d.carromPieces,
      carromBoard: j['carromBoard'] as String? ?? d.carromBoard,
      ludoBoard: j['ludoBoard'] as String? ?? d.ludoBoard,
      ownedPoolTables: _owned(j['ownedPoolTables'], const ['pro_teal', 'pro_green', 'pro_blue'], j['tableSkin'] as String? ?? d.tableSkin),
      ownedCarromBoards: _owned(j['ownedCarromBoards'], const ['classic', 'walnut'], j['carromBoard'] as String? ?? d.carromBoard),
      ownedLudoBoards: _owned(j['ownedLudoBoards'], const ['classic'], j['ludoBoard'] as String? ?? d.ludoBoard),
      languageCode: _normalizeLang(j['languageCode'] as String? ?? d.languageCode),
      challengesEnabled: j['challengesEnabled'] as bool? ?? d.challengesEnabled,
      challengePoolEnabled: j['challengePoolEnabled'] as bool? ?? j['challengesEnabled'] as bool? ?? d.challengePoolEnabled,
      challengeLudoEnabled: j['challengeLudoEnabled'] as bool? ?? j['challengesEnabled'] as bool? ?? d.challengeLudoEnabled,
      challengeCarromEnabled: j['challengeCarromEnabled'] as bool? ?? j['challengesEnabled'] as bool? ?? d.challengeCarromEnabled,
    );
  }

  static String _normalizeLang(String code) => code == 'bn' ? 'bn' : 'en';

  static List<String> _owned(Object? raw, List<String> free, String selected) {
    final extra = raw is List ? [for (final e in raw) e.toString()] : const <String>[];
    return {...free, selected, ...extra}.toList();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatar,
        'coins': coins,
        'wins': wins,
        'games': games,
        'soundOn': soundOn,
        'shotSeconds': shotSeconds,
        'tableSkin': tableSkin,
        'botLevel': botLevel,
        'authToken': authToken,
        'onboarded': onboarded,
        'carromStriker': carromStriker,
        'carromPieces': carromPieces,
        'carromBoard': carromBoard,
        'ludoBoard': ludoBoard,
        'ownedPoolTables': ownedPoolTables,
        'ownedCarromBoards': ownedCarromBoards,
        'ownedLudoBoards': ownedLudoBoards,
        'languageCode': languageCode,
        'challengesEnabled': challengesEnabled,
        'challengePoolEnabled': challengePoolEnabled,
        'challengeLudoEnabled': challengeLudoEnabled,
        'challengeCarromEnabled': challengeCarromEnabled,
      };
}

final storageProvider = Provider<AppStorage>((ref) => MemoryStorage());

final audioProvider = Provider<AudioService>((ref) {
  final audio = AudioService();
  AudioService.instance = audio;
  ref.onDispose(audio.dispose);
  return audio;
});

final cloudinaryProvider = Provider<CloudinaryService>((ref) => CloudinaryService());

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final settings = AppSettings.fromJson(ref.read(storageProvider).load());
    ref.read(audioProvider).soundEnabled = settings.soundOn;
    return settings;
  }

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    ref.read(audioProvider).soundEnabled = state.soundOn;
    ref.read(storageProvider).save(state.toJson());
  }

  /// Local practice only — wins/games for fun stats, no Pico coin.
  void recordPractice({required bool won}) {
    update((s) => s.copyWith(
          games: s.games + 1,
          wins: s.wins + (won ? 1 : 0),
        ));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
