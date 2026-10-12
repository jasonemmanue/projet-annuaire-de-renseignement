// ============================================================
// FICHIER : lib/utils/photo_source.dart
// Choix « Prendre une photo » / « Importer depuis la galerie » partagé
// (photo de profil, CNI, messagerie…), avec demande de permission.
// ============================================================

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'media_permission.dart';

/// Ouvre la feuille de choix puis l'appareil photo ou la galerie.
/// Renvoie null si l'utilisateur annule ou refuse la permission.
Future<XFile?> choisirPhoto(BuildContext context, {int qualite = 80}) async {
  final l = AppLocalizations.of(context);
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
          title: Text(l.t('photo_take')),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
          title: Text(l.t('photo_gallery')),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null || !context.mounted) return null;
  final type = source == ImageSource.camera ? MediaType.camera : MediaType.photos;
  if (!await demanderPermissionMedia(context, type)) return null;
  return ImagePicker().pickImage(source: source, imageQuality: qualite, maxWidth: 2000);
}
