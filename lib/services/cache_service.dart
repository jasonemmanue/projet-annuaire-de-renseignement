// ============================================================
// FICHIER : lib/services/cache_service.dart
// Cache local des logements via SharedPreferences
// Objectif : support hors-connexion sur réseau 3G instable
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class CacheService {
  static const String _cleCache = 'cache_logements';
  static const String _cleCacheDate = 'cache_logements_date';
  static const int _maxLogements = 50;

  // ── Sauvegarde ──────────────────────────────────────────────
  /// Sérialise et sauvegarde jusqu'à [_maxLogements] logements.
  /// Écrase le cache précédent et met à jour le timestamp.
  static Future<void> sauvegarderLogements(List<Logement> logements) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Limite à 50 pour ne pas saturer SharedPreferences
      final aLimiter = logements.take(_maxLogements).toList();

      final jsonList = aLimiter.map((l) => l.toJson()).toList();
      final encoded = jsonEncode(jsonList);

      await prefs.setString(_cleCache, encoded);
      await prefs.setString(
        _cleCacheDate,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      // On ne lève pas : un échec de cache ne doit jamais bloquer l'UI
      debugPrint('[CacheService] Erreur sauvegarde : $e');
    }
  }

  // ── Chargement ──────────────────────────────────────────────
  /// Désérialise les logements depuis SharedPreferences.
  /// Retourne une liste vide si le cache est absent ou corrompu.
  static Future<List<Logement>> chargerLogements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_cleCache);
      if (encoded == null || encoded.isEmpty) return [];

      final jsonList = jsonDecode(encoded) as List<dynamic>;
      return jsonList
          .map((item) => Logement.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CacheService] Erreur chargement : $e');
      return [];
    }
  }

  // ── Date du cache ───────────────────────────────────────────
  /// Retourne la date du dernier cache, ou null si absent.
  static Future<DateTime?> getCacheDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateStr = prefs.getString(_cleCacheDate);
      if (dateStr == null) return null;
      return DateTime.tryParse(dateStr);
    } catch (e) {
      debugPrint('[CacheService] Erreur lecture date : $e');
      return null;
    }
  }

  // ── Vidage ──────────────────────────────────────────────────
  /// Supprime les deux clés de cache.
  static Future<void> viderCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cleCache);
      await prefs.remove(_cleCacheDate);
    } catch (e) {
      debugPrint('[CacheService] Erreur vidage : $e');
    }
  }

  // ── Utilitaire ──────────────────────────────────────────────
  /// Vrai si un cache existe (peu importe son âge).
  static Future<bool> cacheExiste() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_cleCache);
    } catch (_) {
      return false;
    }
  }
}