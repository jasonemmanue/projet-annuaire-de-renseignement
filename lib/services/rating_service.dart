import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_identity.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

// ============================================================
// SERVICE : RatingService
// Gère l'invitation périodique à noter l'application.
// Règles : ≥ 5 ouvertures, 1 fois par 30 jours, jamais si
// l'utilisateur a décliné définitivement.
// ============================================================

class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  static const _kOpenCount   = 'app_open_count';
  static const _kLastAsked   = 'rating_last_asked';
  static const _kDeclined    = 'rating_declined';
  static const _kMinOpens    = 5;
  static const _kDaysBetween = 30;

  // ── Ouvre la fiche de l'app sur le store de la plateforme ────
  // `openStoreListing` attend l'identifiant **numérique** App Store sur iOS
  // (pas le bundle ID) : tant que `AppIdentity.appStoreId` est vide, on ne
  // tente rien plutôt que d'ouvrir une URL invalide. Sur Android le plugin
  // résout la fiche via le package, avec repli navigateur.
  static Future<void> ouvrirFicheStore() async {
    final review = InAppReview.instance;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (!AppIdentity.hasAppStoreId) return;
      await review.openStoreListing(appStoreId: AppIdentity.appStoreId);
      return;
    }

    try {
      await review.openStoreListing();
    } catch (_) {
      final uri = AppIdentity.playStoreUri;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ── Incrémente le compteur d'ouvertures ──────────────────
  Future<void> incrementOpenCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kOpenCount) ?? 0) + 1;
    await prefs.setInt(_kOpenCount, count);
  }

  // ── Vérifie et affiche l'invitation si les conditions sont remplies ──
  Future<void> maybeAskForReview(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    // Déclin définitif
    if (prefs.getBool(_kDeclined) == true) return;

    final openCount = prefs.getInt(_kOpenCount) ?? 0;
    if (openCount < _kMinOpens) return;

    // Délai 30 jours
    final lastAskedStr = prefs.getString(_kLastAsked);
    if (lastAskedStr != null) {
      final lastAsked = DateTime.tryParse(lastAskedStr);
      if (lastAsked != null &&
          DateTime.now().difference(lastAsked).inDays < _kDaysBetween) {
        return;
      }
    }

    if (!context.mounted) return;
    await _showBottomSheet(context, prefs);
  }

  Future<void> _showBottomSheet(
      BuildContext context, SharedPreferences prefs) async {
    final l = AppLocalizations.of(context);
    await prefs.setString(_kLastAsked, DateTime.now().toIso8601String());

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.star_rounded, color: AppColors.accent, size: 52),
            const SizedBox(height: 12),
            Text(l.t('rating_title'),
                style: AppTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.t('rating_body'),
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),

            // Oui — noter
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final review = InAppReview.instance;
                if (await review.isAvailable()) {
                  await review.requestReview();
                } else {
                  await ouvrirFicheStore();
                }
              },
              icon: const Icon(Icons.star_outline),
              label: Text(l.t('rating_yes')),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),

            // Plus tard
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l.t('rating_later')),
            ),
            const SizedBox(height: 8),

            // Non merci
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await prefs.setBool(_kDeclined, true);
              },
              child: Text(l.t('rating_no'),
                  style: const TextStyle(color: AppColors.textHint)),
            ),
          ],
        ),
      ),
    );
  }
}
