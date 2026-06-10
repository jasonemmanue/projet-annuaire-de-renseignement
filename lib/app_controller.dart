import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// AppController — Singleton pour piloter le thème et la langue
// depuis n'importe quel écran sans accéder à _ImmoConnectAppState
// ============================================================
class AppController extends ChangeNotifier {
  AppController._();
  static final AppController instance = AppController._();

  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale('fr');

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get isDark => _themeMode == ThemeMode.dark;

  /// Charge les préférences persistées. À appeler dans main() avant runApp.
  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool('theme_mode') ?? false;
    final code = prefs.getString('locale_code') ?? 'fr';
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_mode', _themeMode == ThemeMode.dark);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale_code', locale.languageCode);
  }
}
