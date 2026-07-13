import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

enum MediaType { photos, camera, videos }

Future<bool> demanderPermissionMedia(
  BuildContext context,
  MediaType type,
) async {
  if (type == MediaType.camera) {
    return _demanderUnePermission(context, Permission.camera, type);
  }

  if (Platform.isAndroid) {
    return _demanderPermissionAndroid(context, type);
  }

  return _demanderUnePermission(context, Permission.photos, type);
}

Future<bool> _demanderPermissionAndroid(
  BuildContext context,
  MediaType type,
) async {
  final granulaire =
      type == MediaType.videos ? Permission.videos : Permission.photos;

  var status = await granulaire.status;
  if (status.isGranted || status.isLimited) return true;

  final storageStatus = await Permission.storage.status;
  if (storageStatus.isGranted || storageStatus.isLimited) return true;

  if (status.isPermanentlyDenied && storageStatus.isPermanentlyDenied) {
    if (!context.mounted) return false;
    await _afficherDialogParametres(context, type);
    return false;
  }

  if (!context.mounted) return false;
  final accepted = await _afficherDialogDemande(context, type);
  if (!accepted) return false;

  // API 33+ : permission granulaire
  if (!status.isPermanentlyDenied) {
    status = await granulaire.request();
    if (status.isGranted || status.isLimited) return true;
  }

  // API < 33 : fallback vers storage
  if (!storageStatus.isPermanentlyDenied) {
    final sResult = await Permission.storage.request();
    if (sResult.isGranted || sResult.isLimited) return true;
  }

  if (context.mounted) {
    await _afficherDialogParametres(context, type);
  }
  return false;
}

Future<bool> _demanderUnePermission(
  BuildContext context,
  Permission permission,
  MediaType type,
) async {
  var status = await permission.status;

  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied) {
    if (!context.mounted) return false;
    await _afficherDialogParametres(context, type);
    return false;
  }

  if (!context.mounted) return false;
  final accepted = await _afficherDialogDemande(context, type);
  if (!accepted) return false;

  status = await permission.request();
  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied && context.mounted) {
    await _afficherDialogParametres(context, type);
  }
  return false;
}

Future<bool> _afficherDialogDemande(
  BuildContext context,
  MediaType type,
) async {
  final l = AppLocalizations.of(context);
  final titleKey = switch (type) {
    MediaType.photos => 'perm_photos_title',
    MediaType.camera => 'perm_camera_title',
    MediaType.videos => 'perm_videos_title',
  };
  final messageKey = switch (type) {
    MediaType.photos => 'perm_photos_message',
    MediaType.camera => 'perm_camera_message',
    MediaType.videos => 'perm_videos_message',
  };
  final icon = switch (type) {
    MediaType.photos => Icons.photo_library_outlined,
    MediaType.camera => Icons.camera_alt_outlined,
    MediaType.videos => Icons.videocam_outlined,
  };

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(icon, size: 48, color: AppColors.primary),
      title: Text(l.t(titleKey), textAlign: TextAlign.center),
      content: Text(l.t(messageKey), textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.t('perm_cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(l.t('perm_allow')),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> _afficherDialogParametres(
  BuildContext context,
  MediaType type,
) async {
  final l = AppLocalizations.of(context);
  final titleKey = switch (type) {
    MediaType.photos => 'perm_photos_title',
    MediaType.camera => 'perm_camera_title',
    MediaType.videos => 'perm_videos_title',
  };

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.settings_outlined, size: 48, color: AppColors.warning),
      title: Text(l.t(titleKey), textAlign: TextAlign.center),
      content: Text(l.t('perm_denied_permanently'), textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.t('perm_cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(l.t('perm_open_settings')),
        ),
      ],
    ),
  );
}
