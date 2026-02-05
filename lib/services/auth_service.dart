import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://att.igenhr.com/api";
  static const String tokenUrl = "$baseUrl/token/";
  static const String refreshUrl = "$baseUrl/token/refresh/";

  static Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse(tokenUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("access", data["access"] as String);
      await prefs.setString("refresh", data["refresh"] as String);
      return true;
    } else {
      return false;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("access") != null;
  }
}
