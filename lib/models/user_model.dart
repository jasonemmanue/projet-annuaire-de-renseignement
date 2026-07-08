import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { client, prestataire, admin }

class UserModel {
  final String id;
  final String? email;
  final String nom;
  final String prenom;
  final String telephone;
  final UserRole role;
  final bool isPremium;
  final String? photoUrl;
  final String? fcmToken;
  final bool isVerifie;
  final bool phoneVerified;
  final bool compteGratuit;
  final DateTime? premiumExpiry;
  final DateTime? phoneVerifiedAt;

  UserModel({
    required this.id,
    this.email,
    required this.nom,
    required this.prenom,
    this.telephone = '',
    required this.role,
    this.isPremium = false,
    this.photoUrl,
    this.fcmToken,
    this.isVerifie = false,
    this.phoneVerified = false,
    this.compteGratuit = false,
    this.premiumExpiry,
    this.phoneVerifiedAt,
  });

  /// Vrai si l'abonnement Premium est actif ET non expiré.
  bool get isPremiumActif =>
      isPremium &&
      (premiumExpiry == null || premiumExpiry!.isAfter(DateTime.now()));

  bool get isPrestataire => role == UserRole.prestataire;
  bool get isAdmin => role == UserRole.admin;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['uid'] ?? '',
      email: map['email'] as String?,
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
      isVerifie:     map['isVerifie']     ?? false,
      phoneVerified: map['phoneVerified'] ?? false,
      compteGratuit: map['compteGratuit'] ?? false,
      premiumExpiry: map['premiumExpiry'] is Timestamp
          ? (map['premiumExpiry'] as Timestamp).toDate()
          : null,
      phoneVerifiedAt: map['phoneVerifiedAt'] is Timestamp
          ? (map['phoneVerifiedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': id,
      'email': email ?? '',
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
      'isVerifie':     isVerifie,
      'phoneVerified': phoneVerified,
      'compteGratuit': compteGratuit,
      if (premiumExpiry   != null)
        'premiumExpiry':   Timestamp.fromDate(premiumExpiry!),
      if (phoneVerifiedAt != null)
        'phoneVerifiedAt': Timestamp.fromDate(phoneVerifiedAt!),
    };
  }
}
