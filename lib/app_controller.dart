import 'package:flutter/material.dart';

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

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }
}
