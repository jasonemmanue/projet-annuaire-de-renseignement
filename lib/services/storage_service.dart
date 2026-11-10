import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// Envoi des fichiers sur le stockage de l'API (volume Railway).
class StorageService {
  static final _api = ApiClient.instance;

  // Upload une photo de logement
  static Future<String> uploadLogementPhoto({
    required String uid,
    required String logementId,
    required XFile image,
  }) =>
      _api.envoyerFichier('logements', image.path, nom: 'photo.jpg');

  // Upload plusieurs photos
  static Future<List<String>> uploadMultiplePhotos({
    required String uid,
    required String logementId,
    required List<XFile> images,
  }) =>
      Future.wait(images.map((img) => uploadLogementPhoto(
            uid: uid,
            logementId: logementId,
            image: img,
          )));

  // Upload photo de profil
  static Future<String> uploadProfilePhoto({
    required String uid,
    required XFile image,
  }) =>
      _api.envoyerFichier('profils', image.path, nom: 'photo.jpg');

  // Upload CNI (recto / verso) : lecture réservée au titulaire et aux admins.
  static Future<String> uploadCni({
    required String uid,
    required String face,
    required XFile image,
  }) =>
      _api.envoyerFichier('cni', image.path, nom: '$face.jpg');
}
