import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthStateManager {
  static final AuthStateManager _instance = AuthStateManager._internal();
  factory AuthStateManager() => _instance;
  AuthStateManager._internal();

  User? _currentUser;

  static const String _tokenKey = 'auth_token';
  static const String _userDataKey = 'user_data';

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  // ─── Сессия ───────────────────────────────────────────────────────────────

  Future<void> setUser(User user) async {
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, user.token);
    await prefs.setString(_userDataKey, json.encode(user.toJson()));
  }

  Future<void> clearUser() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userDataKey);
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Инициализация при запуске — восстанавливаем сессию из локального кэша
  /// без запроса к серверу. Работает полностью офлайн.
  Future<bool> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userDataJson = prefs.getString(_userDataKey);

      if (token == null || token.isEmpty || userDataJson == null) {
        return false;
      }

      final userData = json.decode(userDataJson) as Map<String, dynamic>;
      _currentUser = User(
        phone: userData['phone']?.toString() ?? '',
        token: token,
        name: userData['name']?.toString(),
        surname: userData['surname']?.toString(),
        patronymic: userData['patronymic']?.toString(),
        iin: userData['iin']?.toString(),
      );

      debugPrint('[Auth] Session restored: ${_currentUser!.phone}');
      return true;
    } catch (e) {
      debugPrint('[Auth] Init error: $e');
      return false;
    }
  }

  // ─── Отображение имени ─────────────────────────────────────────────────────

  String getDisplayName() {
    if (_currentUser == null) return '';
    final surname = _currentUser!.surname ?? '';
    final name = _currentUser!.name ?? '';
    if (surname.isEmpty && name.isEmpty) return _currentUser!.phone;
    if (surname.isNotEmpty && name.isNotEmpty) {
      return '${surname[0].toUpperCase()}. $name';
    }
    return name.isNotEmpty ? name : surname;
  }
}
