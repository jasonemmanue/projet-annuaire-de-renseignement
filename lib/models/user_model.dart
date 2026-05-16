enum UserRole { client, prestataire, admin }

class UserModel {
  final String id;
  final String email;
  final String nom;
  final String prenom;
  final String telephone;
  final UserRole role;
  final bool isPremium;
  final String? photoUrl;
  final String? fcmToken;
  final bool isVerifie; // ✅ Statut vérifié prestataire

  UserModel({
    required this.id,
    required this.email,
    required this.nom,
    required this.prenom,
    this.telephone = '',
    required this.role,
    this.isPremium = false,
    this.photoUrl,
    this.fcmToken,
    this.isVerifie = false,
  });

  bool get isPrestataire => role == UserRole.prestataire;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['uid'] ?? '',
      email: map['email'] ?? '',
      nom: map['nom'] ?? '',
      prenom: map['prenom'] ?? '',
      telephone: map['telephone'] ?? '',
      role: map['role'] == 'prestataire'
          ? UserRole.prestataire
          : map['role'] == 'admin'
          ? UserRole.admin
          : UserRole.client,
      isPremium: map['isPremium'] ?? false,
      photoUrl: map['photoUrl'],
      fcmToken: map['fcmToken'],
      isVerifie: map['isVerifie'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': id,
      'email': email,
      'nom': nom,
      'prenom': prenom,
      'telephone': telephone,
      'role': role == UserRole.prestataire
          ? 'prestataire'
          : role == UserRole.admin
          ? 'admin'
          : 'client',
      'isPremium': isPremium,
      'photoUrl': photoUrl,
      'fcmToken': fcmToken,
      'isVerifie': isVerifie,
    };
  }
}
