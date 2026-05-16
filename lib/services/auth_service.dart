import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';

class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _loadUserFromFirestore(firebaseUser.uid);
    }
  }

  Future<void> _loadUserFromFirestore(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      _currentUser = UserModel.fromMap(doc.data()!);
    } else {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        final minimal = UserModel(
          id: uid,
          email: firebaseUser.email ?? '',
          nom: '',
          prenom: '',
          role: UserRole.prestataire,
        );
        await _db.collection('users').doc(uid).set({
          ...minimal.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        _currentUser = minimal;
      }
    }
  }

  Future<AuthResult> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _loadUserFromFirestore(cred.user!.uid);

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('users').doc(cred.user!.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
      }

      if (_currentUser?.role != UserRole.prestataire) {
        await _auth.signOut();
        _currentUser = null;
        return AuthResult.wrongCredentials;
      }

      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' ||
          e.code == 'invalid-credential' || e.code == 'invalid-email') {
        return AuthResult.wrongCredentials;
      }
      return AuthResult.networkError;
    }
  }

  /// Inscription prestataire avec photo de profil optionnelle
  Future<AuthResult> register({
    required String email,
    required String password,
    required String nom,
    required String prenom,
    required String telephone,
    String? photoUrl, // ✅ Photo de profil
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final token = await FirebaseMessaging.instance.getToken();

      final user = UserModel(
        id: cred.user!.uid,
        email: email.trim(),
        nom: nom,
        prenom: prenom,
        telephone: telephone,
        role: UserRole.prestataire,
        fcmToken: token,
        photoUrl: photoUrl,
        isVerifie: false,
      );

      await _db.collection('users').doc(cred.user!.uid).set({
        ...user.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      _currentUser = user;
      return AuthResult.success;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return AuthResult.emailAlreadyUsed;
      }
      return AuthResult.networkError;
    } catch (e) {
      return AuthResult.networkError;
    }
  }

  /// Met à jour la photo de profil dans Firestore et en mémoire
  Future<void> updatePhotoUrl(String photoUrl) async {
    if (_currentUser == null) return;
    await _db.collection('users').doc(_currentUser!.id).set(
      {'photoUrl': photoUrl},
      SetOptions(merge: true),
    );
    _currentUser = UserModel(
      id: _currentUser!.id,
      email: _currentUser!.email,
      nom: _currentUser!.nom,
      prenom: _currentUser!.prenom,
      telephone: _currentUser!.telephone,
      role: _currentUser!.role,
      isPremium: _currentUser!.isPremium,
      photoUrl: photoUrl,
      fcmToken: _currentUser!.fcmToken,
      isVerifie: _currentUser!.isVerifie,
    );
  }

  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
  }
}

enum AuthResult { success, wrongCredentials, emailAlreadyUsed, networkError }
