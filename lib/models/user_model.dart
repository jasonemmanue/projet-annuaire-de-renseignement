// ============================================================
// FICHIER : lib/models/user_model.dart
// Modèle utilisateur + gestion du rôle prestataire
// ============================================================

/// Rôles disponibles dans l'application
enum UserRole { client, prestataire }

/// Modèle de l'utilisateur connecté
class UserModel {
  final String id;
  final String email;
  final String nom;
  final String prenom;
  final UserRole role;

  const UserModel({
    required this.id,
    required this.email,
    required this.nom,
    required this.prenom,
    required this.role,
  });

  bool get isPrestataire => role == UserRole.prestataire;

  /// Nom complet affiché dans l'UI
  String get fullName => '$prenom $nom';
}