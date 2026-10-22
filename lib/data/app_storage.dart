import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key-value persistence for the local profile and settings. The demo build
/// keeps everything on the device; an online backend can provide another
/// implementation without touching the UI.
abstract class AppStorage {
  Map<String, dynamic> load();
  Future<void> save(Map<String, dynamic> data);
}

class PrefsStorage implements AppStorage {
  PrefsStorage._(this._prefs, this._secure, this._profile);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  Map<String, dynamic> _profile;

  static const _profileKey = 'billiard_poker_profile_v1';
  static const _tokenKey = 'auth_token';

  static const _tokenStore = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static Future<PrefsStorage> open() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsStorage._(prefs, _tokenStore, {});
    await storage._hydrate();
    return storage;
  }

  Future<void> _hydrate() async {
    final raw = _prefs.getString(_profileKey);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        map = {};
      }
    }
    final legacy = map.remove('authToken');
    var token = '';
    try {
      token = await _secure.read(key: _tokenKey) ?? '';
    } catch (_) {
      token = legacy is String ? legacy : '';
    }
    if (token.isEmpty && legacy is String && legacy.isNotEmpty) {
      token = legacy;
      try {
        await _secure.write(key: _tokenKey, value: token);
      } catch (_) {}
      await _prefs.setString(_profileKey, jsonEncode(map));
    }
    map['authToken'] = token;
    _profile = map;
  }

  @override
  Map<String, dynamic> load() => Map<String, dynamic>.from(_profile);

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final token = data['authToken'] as String? ?? '';
    if (token.isEmpty) {
      await _secure.delete(key: _tokenKey);
    } else {
      await _secure.write(key: _tokenKey, value: token);
    }
    final prefsJson = Map<String, dynamic>.from(data)..remove('authToken');
    await _prefs.setString(_profileKey, jsonEncode(prefsJson));
    _profile = {...prefsJson, 'authToken': token};
  }
}

class MemoryStorage implements AppStorage {
  Map<String, dynamic> _data = {};

  @override
  Map<String, dynamic> load() => _data;

  @override
  Future<void> save(Map<String, dynamic> data) async => _data = data;
}
