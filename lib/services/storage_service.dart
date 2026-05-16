import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static final _storage = FirebaseStorage.instance;

  // Upload une photo de logement
  static Future<String> uploadLogementPhoto({
    required String uid,
    required String logementId,
    required XFile image,
  }) async {
    final ref = _storage
        .ref()
        .child('logements/$uid/$logementId/${DateTime.now().millisecondsSinceEpoch}.jpg');

    final task = await ref.putFile(
      File(image.path),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }

  // Upload plusieurs photos
  static Future<List<String>> uploadMultiplePhotos({
    required String uid,
    required String logementId,
    required List<XFile> images,
  }) async {
    final urls = await Future.wait(
      images.map((img) => uploadLogementPhoto(
        uid: uid,
        logementId: logementId,
        image: img,
      )),
    );
    return urls;
  }

  // Upload photo de profil
  static Future<String> uploadProfilePhoto({
    required String uid,
    required XFile image,
  }) async {
    final ref = _storage
        .ref()
        .child('profils/$uid/avatar.jpg');

    final task = await ref.putFile(
      File(image.path),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await task.ref.getDownloadURL();
  }

  // Supprimer une photo
  static Future<void> deletePhoto(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      // Ignore si déjà supprimée
    }
  }
}