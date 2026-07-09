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
  final permission = _permissionPour(type);
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

Permission _permissionPour(MediaType type) {
  switch (type) {
    case MediaType.photos:
      if (Platform.isAndroid) return Permission.photos;
      return Permission.photos;
    case MediaType.camera:
      return Permission.camera;
    case MediaType.videos:
      if (Platform.isAndroid) return Permission.videos;
      return Permission.photos;
  }
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
