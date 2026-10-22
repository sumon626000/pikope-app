import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import '../../data/api_client.dart';
import '../../core/bd_phone.dart';
import '../../data/app_game.dart';

/// JSON numbers sometimes arrive as int, double, or a numeric string.
int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round() ?? fallback;
  return fallback;
}

List<String>? _idList(Object? raw) {
  if (raw is! List) return null;
  return [for (final e in raw) e.toString()];
}

/// The backend, or null in a build without `API_BASE_URL`.
final apiProvider = Provider<ApiClient?>((ref) {
  if (!Env.hasBackend) return null;
  final api = ApiClient(Env.apiBaseUrl);
  ref.onDispose(api.close);
  return api;
});

class SessionState {
  const SessionState({this.user});

  /// The signed-in user as the server describes it, or null.
  final Map<String, dynamic>? user;

  bool get signedIn => user != null;
  int get gems => _asInt(user?['gems']);
  int get level => _asInt(user?['level'], 1);
  int get levelProgress => _asInt(user?['levelProgress']);
  String get rankName {
    final rank = user?['rank'];
    if (rank is Map) {
      final name = rank['name']?.toString();
      if (name != null && name.isNotEmpty) return name;
    }
    if (rank is String && rank.isNotEmpty) return rank;
    return 'BRONZE I';
  }

  int get rankTier {
    final rank = user?['rank'];
    if (rank is Map) return _asInt(rank['tier']);
    return 0;
  }
  String get cue => user?['cue'] as String? ?? 'classic';
  List<String> get cues => (user?['cues'] as List?)?.cast<String>() ?? const ['classic'];

  /// The player has chosen a nickname (the create-profile step is done).
  bool get nameSet => user?['nameSet'] as bool? ?? false;

  /// When the next rename is allowed (UTC), or null if a rename is allowed now.
  DateTime? get nameChangeAllowedAt {
    final raw = user?['nameChangeAllowedAt'];
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  bool get canChangeName {
    final at = nameChangeAllowedAt;
    return at == null || !DateTime.now().toUtc().isBefore(at.toUtc());
  }
  bool get isGuest => user?['isGuest'] as bool? ?? true;
  String? get phone => user?['phone'] as String?;
  int? get userId => user?['id'] as int?;
  int get walletCoins => _asInt(user?['coins']);
  int get redeemableCoins => _asInt(user?['redeemableCoins']);
}

/// Account on the backend. Playing online needs no sign-up: a guest account
/// is created on first use and can be given a mobile login and password later.
class SessionNotifier extends Notifier<SessionState> {
  ApiClient get _api => ref.read(apiProvider)!;

  @override
  SessionState build() {
    final token = ref.read(settingsProvider).authToken;
    final api = ref.read(apiProvider);
    if (api != null && token.isNotEmpty) api.token = token;
    return const SessionState();
  }

  /// The server decides coins and wins; name, avatar and table follow it too.
  void _adopt(Map<String, dynamic> user, {String? token}) {
    if (token != null) _api.token = token;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          authToken: token ?? s.authToken,
          name: user['displayName']?.toString().trim().isNotEmpty == true
              ? user['displayName'].toString()
              : s.name,
          avatar: user['avatar']?.toString().isNotEmpty == true
              ? user['avatar'].toString()
              : s.avatar,
          tableSkin: user['ownedPoolTables'] is List && user['tableSkin']?.toString().isNotEmpty == true
              ? user['tableSkin'].toString()
              : s.tableSkin,
          carromBoard: user['carromBoard']?.toString().isNotEmpty == true
              ? user['carromBoard'].toString()
              : s.carromBoard,
          ludoBoard: user['ludoBoard']?.toString().isNotEmpty == true
              ? user['ludoBoard'].toString()
              : s.ludoBoard,
          ownedPoolTables: _idList(user['ownedPoolTables']) ?? s.ownedPoolTables,
          ownedCarromBoards: _idList(user['ownedCarromBoards']) ?? s.ownedCarromBoards,
          ownedLudoBoards: _idList(user['ownedLudoBoards']) ?? s.ownedLudoBoards,
          challengesEnabled: user['challengesEnabled'] as bool? ?? s.challengesEnabled,
          challengePoolEnabled: user['challengePoolEnabled'] as bool? ?? s.challengePoolEnabled,
          challengeLudoEnabled: user['challengeLudoEnabled'] as bool? ?? s.challengeLudoEnabled,
          challengeCarromEnabled: user['challengeCarromEnabled'] as bool? ?? s.challengeCarromEnabled,
          coins: _asInt(user['coins'], s.coins),
          wins: _asInt(user['wins'], s.wins),
          games: _asInt(user['games'], s.games),
        ));
    state = SessionState(user: user);
  }

  /// Takes over what the server says about this account.
  void adopt(Map<String, dynamic> user) => _adopt(user);

  /// Renames the account. The server allows this once every 7 days.
  Future<void> saveDisplayName(String name) async {
    await ensureSignedIn();
    final r = await _api.patch('/me', {'displayName': name});
    _adopt(r['user'] as Map<String, dynamic>);
  }

  /// Sets nickname and avatar; throws [ApiException] if the name is refused.
  Future<void> saveProfile(String name, String avatar) async {
    await ensureSignedIn();
    final r = await _api.patch('/me', {'displayName': name, 'avatar': avatar});
    _adopt(r['user'] as Map<String, dynamic>);
  }

  /// The player's latest matches, newest first.
  Future<List<Map<String, dynamic>>> history() async {
    await ensureSignedIn();
    return ((await _api.get('/me/history'))['matches'] as List).cast<Map<String, dynamic>>();
  }

  /// Matches, wallet movements, shop and redeem — newest first.
  Future<List<Map<String, dynamic>>> activity({int limit = 60}) async {
    await ensureSignedIn();
    return ((await _api.get('/me/activity?limit=$limit'))['items'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> startZiniPayDeposit(int bdt, {String? packId, int qty = 1}) async {
    await ensureSignedIn();
    final body = <String, dynamic>{'bdt': bdt, 'qty': qty};
    if (packId != null && packId.isNotEmpty) body['packId'] = packId;
    return await _api.post('/deposit/zinipay/start', body);
  }

  Future<Map<String, dynamic>> finishZiniPayDeposit(int depositId) async {
    await ensureSignedIn();
    final r = await _api.post('/deposit/zinipay/finish', {'depositId': depositId});
    _adopt(r['user'] as Map<String, dynamic>);
    return r;
  }

  Future<Map<String, dynamic>> submitDeposit({
    required int bdt,
    required String provider,
    required String trxId,
    required String payerNumber,
  }) async {
    await ensureSignedIn();
    final r = await _api.post('/deposit/request', {
      'bdt': bdt,
      'provider': provider,
      'trxId': trxId.trim(),
      'payerNumber': payerNumber.trim(),
    });
    _adopt(r['user'] as Map<String, dynamic>);
    return r['request'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitRedeem({
    required int coins,
    required String walletProvider,
    required String walletNumber,
  }) async {
    await ensureSignedIn();
    final r = await _api.post('/redeem/request', {
      'coins': coins,
      'walletProvider': walletProvider,
      'walletNumber': walletNumber,
    });
    _adopt(r['user'] as Map<String, dynamic>);
    return r['request'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> redeemRequests({int limit = 20}) async {
    await ensureSignedIn();
    return ((await _api.get('/me/redeems'))['requests'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> cancelRedeem(int id) async {
    await ensureSignedIn();
    final r = await _api.post('/redeem/cancel', {'id': id});
    _adopt(r['user'] as Map<String, dynamic>);
    return r['request'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> lookupTransferTarget(String gameId) async {
    await ensureSignedIn();
    final code = gameId.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) return null;
    try {
      return (await _api.get('/transfer/lookup?gameId=$code'))['profile'] as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.code == 'not_found' || e.status == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendCoinTransfer({required String gameId, required int amount}) async {
    await ensureSignedIn();
    final code = gameId.replaceAll(RegExp(r'\D'), '');
    final r = await _api.post('/transfer/send', {'gameId': code, 'amount': amount});
    final user = r['user'];
    if (user is Map<String, dynamic>) {
      _adopt(user);
    } else if (user is Map) {
      _adopt(Map<String, dynamic>.from(user));
    }
    final transfer = r['transfer'];
    if (transfer is Map<String, dynamic>) return transfer;
    if (transfer is Map) return Map<String, dynamic>.from(transfer);
    return const {};
  }

  /// Operator announcements to show in the inbox (and home banner).
  Future<List<Map<String, dynamic>>> notices() async {
    await ensureSignedIn();
    return ((await _api.get('/notices'))['notices'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> notifications() async {
    await ensureSignedIn();
    return await _api.get('/me/notifications');
  }

  Future<void> markNotificationsRead({int? id}) async {
    await ensureSignedIn();
    await _api.post('/me/notifications/read', id != null ? {'id': id} : {});
  }

  /// The match this account is still seated in (app was closed, connection
  /// lost ...), or null.
  Future<Map<String, dynamic>?> activeMatch() async {
    if (ref.read(settingsProvider).authToken.isEmpty) return null;
    await ensureSignedIn();
    return (await _api.get('/me/active'))['match'] as Map<String, dynamic>?;
  }

  String? _wsUrl;
  bool _wsAsked = false;

  /// Address of the WebSocket server, or null when the backend has none (the
  /// app then plays over HTTP). Asked once per run.
  Future<String?> realtimeUrl() async {
    if (Env.wsUrl.isNotEmpty) return Env.wsUrl;
    if (_wsAsked) return _wsUrl;
    try {
      _wsUrl = (await _api.get('/config'))['ws'] as String?;
      _wsAsked = true;
    } on ApiException {
      // Ask again next time.
    }
    return _wsUrl;
  }

  Future<void> ensureSignedIn({String referralCode = ''}) async {
    if (!Env.hasBackend) {
      throw ApiException(0, 'offline', 'This build has no game server.');
    }
    if (state.signedIn) return;
    final settings = ref.read(settingsProvider);
    if (settings.authToken.isNotEmpty) {
      try {
        _adopt((await _api.get('/me'))['user'] as Map<String, dynamic>);
        return;
      } on ApiException catch (e) {
        if (e.status != 401) rethrow; // expired session: fall through to a new guest
      }
    }
    final avatar = settings.avatar.startsWith('asset:') ? settings.avatar : 'asset:avatar_1';
    final r = await _api.post('/auth/guest', {
      'displayName': settings.name,
      'avatar': avatar,
    });
    final user = r['user'] as Map<String, dynamic>;
    _api.token = r['token'] as String;
    // A fresh guest keeps the table chosen on this device.
    final synced = await _api.patch('/me', {'tableSkin': settings.tableSkin});
    _adopt(synced['user'] as Map<String, dynamic>? ?? user, token: r['token'] as String);
  }

  Future<void> refresh() async {
    if (!state.signedIn) return;
    _adopt((await _api.get('/me'))['user'] as Map<String, dynamic>);
  }

  /// New mobile account, or add a login to the current guest profile.
  Future<void> register(String phoneLocal, String password, {String referralCode = '', String? displayName}) async {
    if (!Env.hasBackend) {
      throw ApiException(0, 'offline', 'Sign-up needs the game server.');
    }
    final code = referralCode.trim();
    final body = {
      'phone': BdPhone.apiPayload(phoneLocal),
      'password': password,
      if (code.isNotEmpty) 'referralCode': code,
    };
    if (state.signedIn && state.isGuest) {
      final r = await _api.post('/auth/register', body);
      final token = r['token'] as String? ?? _api.token!;
      _adopt(r['user'] as Map<String, dynamic>, token: token);
      return;
    }
    final name = (displayName ?? ref.read(settingsProvider).name).trim();
    final r = await _api.post('/auth/register', {...body, 'displayName': name});
    _adopt(r['user'] as Map<String, dynamic>, token: r['token'] as String);
  }

  Future<void> login(String phoneLocal, String password) async {
    if (!Env.hasBackend) {
      throw ApiException(0, 'offline', 'Log in needs the game server.');
    }
    final previous = _api.token;
    _api.token = null;
    try {
      final r = await _api.post('/auth/login', {'phone': BdPhone.apiPayload(phoneLocal), 'password': password});
      _adopt(r['user'] as Map<String, dynamic>, token: r['token'] as String);
    } catch (_) {
      _api.token = previous;
      rethrow;
    }
  }

  /// Sends an SMS OTP to [phoneLocal] (if that number has an account).
  Future<void> forgotPassword(String phoneLocal) =>
      _api.post('/auth/forgot', {'phone': BdPhone.apiPayload(phoneLocal)});

  /// Sets a new password with the SMS code and signs in.
  Future<void> resetPassword(String phoneLocal, String code, String password) async {
    final previous = _api.token;
    _api.token = null;
    try {
      final r = await _api.post('/auth/reset', {
        'phone': BdPhone.apiPayload(phoneLocal),
        'code': code,
        'password': password,
      });
      _adopt(r['user'] as Map<String, dynamic>, token: r['token'] as String);
    } catch (_) {
      _api.token = previous;
      rethrow;
    }
  }

  Future<void> logout() async {
    final api = ref.read(apiProvider);
    if (api != null) {
      try {
        await api.post('/auth/logout');
      } on ApiException {
        // Signing out locally is what matters.
      }
      api.token = null;
    }
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(authToken: '', onboarded: false));
    state = const SessionState();
  }

  /// Sends name / avatar / table changes made on this device.
  Future<void> pushProfile() async {
    if (!state.signedIn) return;
    final s = ref.read(settingsProvider);
    try {
      final r = await _api.patch('/me', {
        // A name the server would refuse must not hold back the rest.
        if (s.avatar.startsWith('asset:') || s.avatar.startsWith('url:')) 'avatar': s.avatar,
        'tableSkin': s.tableSkin,
      });
      state = SessionState(user: r['user'] as Map<String, dynamic>);
    } on ApiException {
      // Not critical; the next sign-in syncs again.
    }
  }

  Future<void> uploadAvatar(Uint8List bytes, String filename) async {
    await ensureSignedIn();
    final r = await _api.upload('/me/avatar', bytes, filename);
    _adopt(r['user'] as Map<String, dynamic>);
  }

  // ---- 1v1 challenges ----------------------------------------------------

  Future<List<Map<String, dynamic>>> onlinePlayers() async {
    await ensureSignedIn();
    return ((await _api.get('/challenge/online'))['players'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendChallenge(int toUserId, String game, int? level) async {
    await ensureSignedIn();
    return _api.post('/challenge/send', {'toUserId': toUserId, 'game': game, 'level': ?level});
  }

  /// {incoming:[...], outgoing:[...]}
  Future<Map<String, dynamic>> challengeInbox() async {
    if (ref.read(settingsProvider).authToken.isEmpty) return const {'incoming': [], 'outgoing': []};
    await ensureSignedIn();
    return _api.get('/challenge/inbox');
  }

  Future<Map<String, dynamic>> acceptChallenge(int id) async => (await _api.post('/challenge/$id/accept'))['room'] as Map<String, dynamic>;
  Future<void> declineChallenge(int id) => _api.post('/challenge/$id/decline');
  Future<void> cancelChallenge(int id) => _api.post('/challenge/$id/cancel');

  /// Practice vs bots: experience only, no Pico coin.
  Future<void> reportBotMatch(AppGame game, {required bool won}) async {
    final r = await _api.post('/matches/bot', {'game': game.apiName, 'won': won});
    _adopt(r['user'] as Map<String, dynamic>);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Looked up whenever the home screen is shown; errors (offline) count as none.
final activeMatchProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  if (!Env.hasBackend) return null;
  try {
    return await ref.read(sessionProvider.notifier).activeMatch();
  } catch (_) {
    return null;
  }
});
