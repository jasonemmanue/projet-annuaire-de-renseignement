// ============================================================
// FICHIER : lib/utils/session_cache.dart
//
// Cache persistant local des donnees des ecrans dependant du reseau.
// Utilise pour rendre l'ouverture de « Messagerie » instantanee, meme apres
// un redemarrage a froid, sans attendre le premier snapshot Firestore.
// ============================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Instantane serialisable d'une conversation, tel que l'ecran de messagerie
/// a besoin de la rendre : titre, dernier message, non-lus, urgence.
/// Le typage est deliberement souple (Map<String, dynamic>) : les champs
/// Firestore evoluent et un decodeur strict deviendrait la premiere cause de
/// « cache vide » sur ancienne installation.
class SessionCache {
  SessionCache._();

  static const _ttl = Duration(days: 7);

  static String _keyConversations(String uid) => 'cache_conv_$uid';

  static Future<void> saveConversations(
      String uid, List<Map<String, dynamic>> items) async {
    await _save(_keyConversations(uid), items);
  }

  static Future<List<Map<String, dynamic>>?> loadConversations(
      String uid) async {
    final list = await _load(_keyConversations(uid));
    if (list == null) return null;
    return list.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  static Future<void> clearUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyConversations(uid));
    } catch (_) {}
  }

  // ── Primitives ─────────────────────────────────────────────────────

  static Future<void> _save(String key, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'items': items,
      });
      await prefs.setString(key, payload);
    } catch (e) {
      debugPrint('SessionCache: ecriture $key impossible — $e');
    }
  }

  static Future<List<dynamic>?> _load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(map['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > _ttl) {
        return null;
      }
      return map['items'] as List<dynamic>?;
    } catch (e) {
      debugPrint('SessionCache: lecture $key impossible — $e');
      return null;
    }
  }
}
