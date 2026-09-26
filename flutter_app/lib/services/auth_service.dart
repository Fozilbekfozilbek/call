import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';

class AuthResult {
  final AppUser user;
  final String token;
  AuthResult(this.user, this.token);
}

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  Future<AuthResult> login({
    required String phone,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'password': password}),
    );

    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Login xato');
    }

    final user = AppUser.fromJson(body['user']);
    final token = body['token'] as String;
    await _persist(user, token);
    return AuthResult(user, token);
  }

  Future<AuthResult> register({
    required String name,
    required String phone,
    required String password,
    bool asAdmin = false,
    String? adminSecret,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'password': password,
        if (asAdmin) 'role': 'admin',
        if (asAdmin) 'adminSecret': adminSecret,
      }),
    );

    final body = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(body['error'] ?? 'Ro\'yxatdan o\'tishda xato');
    }

    final user = AppUser.fromJson(body['user']);
    final token = body['token'] as String;
    await _persist(user, token);
    return AuthResult(user, token);
  }

  Future<void> _persist(AppUser user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<AuthResult?> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userStr = prefs.getString(_userKey);
    if (token == null || userStr == null) return null;
    final user = AppUser.fromJson(jsonDecode(userStr));
    return AuthResult(user, token);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
