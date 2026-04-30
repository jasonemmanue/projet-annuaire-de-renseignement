// ============================================================
// FICHIER : lib/services/auth_service.dart
// Service d'authentification — données statiques (Phase 1)
// Remplacer plus tard par Firebase Auth / API REST
// ============================================================

import '../models/user_model.dart';

class AuthService {
  // ── Singleton ──────────────────────────────────────────────
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  // ── État ───────────────────────────────────────────────────
  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // ── Comptes statiques de test ──────────────────────────────
  // TODO: remplacer par un appel API / Firebase Auth
  static const List<Map<String, dynamic>> _staticAccounts = [
    {
      'id': 'p001',
      'email': 'sakamemmanuel',   // email ou identifiant
      'password': '123456789',
      'nom': 'SAKAM',
      'prenom': 'Emmanuel',
      'role': UserRole.prestataire,
    },
  ];

  // ── Connexion ──────────────────────────────────────────────
  /// Retourne [AuthResult.success] et renseigne [currentUser],
  /// ou [AuthResult.wrongCredentials] si email/mot de passe incorrect.
  Future<AuthResult> login(String email, String password) async {
    // Simuler un délai réseau
    await Future.delayed(const Duration(milliseconds: 800));

    final match = _staticAccounts.where(
          (a) =>
      a['email'].toString().toLowerCase() == email.trim().toLowerCase() &&
          a['password'] == password,
    );

    if (match.isEmpty) return AuthResult.wrongCredentials;

    final account = match.first;
    _currentUser = UserModel(
      id: account['id'] as String,
      email: account['email'] as String,
      nom: account['nom'] as String,
      prenom: account['prenom'] as String,
      role: account['role'] as UserRole,
    );
    return AuthResult.success;
  }

  // ── Déconnexion ────────────────────────────────────────────
  Future<void> logout() async {
    _currentUser = null;
  }
}

/// Résultat possible d'une tentative de connexion
enum AuthResult {
  success,
  wrongCredentials,
  networkError,
}