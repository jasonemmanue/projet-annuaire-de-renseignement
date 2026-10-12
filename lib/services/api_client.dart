import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ============================================================
// FICHIER : lib/services/api_client.dart
// Client de l'API Horem+ (FastAPI + PostgreSQL sur Railway).
//
// Firestore et les Cloud Functions sont remplacés par cette API.
// Firebase reste utilisé pour : l'authentification (le jeton d'identité
// est envoyé dans Authorization), le stockage des fichiers (Storage) et
// les notifications push (FCM).
//
// Visiteur sans compte : identifiant aléatoire « visiteur_<uuid> » envoyé
// dans l'en-tête X-Visiteur-Id (messagerie, signalements).
//
// « Temps réel » : [ApiClient.sonder] interroge l'API à intervalle régulier
// en envoyant la version connue (?v=…). Tant que rien ne change, le serveur
// répond « inchangé » depuis son cache : très peu coûteux, même avec des
// dizaines de milliers d'utilisateurs.
// ============================================================

/// Adresse de l'API (surchargeable : --dart-define=API_BASE_URL=…).
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://horem-api-production.up.railway.app/api/v1',
);

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  const ApiException(this.statusCode, this.message, {this.code, this.data});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  static const _kVisiteurUid = 'visiteur_uid';
  String? _visiteurId;

  /// Identifiant visiteur stable (créé au premier appel).
  Future<String> visiteurId() async {
    if (_visiteurId != null) return _visiteurId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kVisiteurUid);
    if (id == null) {
      id = 'visiteur_${const Uuid().v4()}';
      await prefs.setString(_kVisiteurUid, id);
    }
    _visiteurId = id;
    return id;
  }

  Future<Map<String, String>> _entetes({bool json = true}) async {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final jeton = await user.getIdToken();
        if (jeton != null) h['Authorization'] = 'Bearer $jeton';
      } catch (e) {
        debugPrint('[API] jeton Firebase indisponible : $e');
      }
    }
    h['X-Visiteur-Id'] = await visiteurId();
    return h;
  }

  Uri _uri(String chemin, [Map<String, dynamic>? params]) {
    final q = <String, String>{};
    params?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return Uri.parse('$kApiBaseUrl$chemin')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  dynamic _decoder(http.Response r) {
    dynamic corps;
    if (r.body.isNotEmpty) {
      try {
        corps = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        corps = r.body;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return corps;
    String message = 'Erreur serveur (${r.statusCode})';
    String? code;
    Map<String, dynamic>? data;
    if (corps is Map<String, dynamic>) {
      data = corps;
      final d = corps['error'] ?? corps['detail'];
      if (d is String) message = d;
      if (d is Map && d['error'] is String) message = d['error'] as String;
      code = corps['code'] as String? ??
          (d is Map ? d['code'] as String? : null);
    }
    throw ApiException(r.statusCode, message, code: code, data: data);
  }

  Future<dynamic> get(String chemin, {Map<String, dynamic>? params}) async {
    final r = await _http
        .get(_uri(chemin, params), headers: await _entetes(json: false))
        .timeout(const Duration(seconds: 25));
    return _decoder(r);
  }

  Future<dynamic> post(String chemin, [Object? corps]) async {
    final r = await _http
        .post(_uri(chemin),
            headers: await _entetes(), body: jsonEncode(corps ?? {}))
        .timeout(const Duration(seconds: 40));
    return _decoder(r);
  }

  Future<dynamic> put(String chemin, [Object? corps]) async {
    final r = await _http
        .put(_uri(chemin), headers: await _entetes(), body: jsonEncode(corps ?? {}))
        .timeout(const Duration(seconds: 25));
    return _decoder(r);
  }

  Future<dynamic> patch(String chemin, [Object? corps]) async {
    final r = await _http
        .patch(_uri(chemin),
            headers: await _entetes(), body: jsonEncode(corps ?? {}))
        .timeout(const Duration(seconds: 25));
    return _decoder(r);
  }

  Future<dynamic> delete(String chemin) async {
    final r = await _http
        .delete(_uri(chemin), headers: await _entetes(json: false))
        .timeout(const Duration(seconds: 25));
    return _decoder(r);
  }

  /// Liste `items` d'une réponse { items: [...] }.
  static List<Map<String, dynamic>> items(dynamic rep) {
    final l = (rep is Map ? rep['items'] : rep) as List? ?? const [];
    return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Sondages en cours, partagés par ressource (chemin + paramètres).
  final Map<String, _Sondage> _sondages = {};

  /// Flux « temps réel » par interrogation versionnée. N'émet que lorsque
  /// les données changent.
  ///
  /// Un SEUL sondage par ressource, quel que soit le nombre d'écrans qui
  /// écoutent ; un nouvel abonné reçoit tout de suite la dernière valeur.
  /// Un écran qui recrée son flux à chaque reconstruction ne relance donc
  /// pas de requête. Le sondage s'arrête 3 s après le départ du dernier
  /// abonné.
  Stream<T> sonder<T>(
    String chemin,
    T Function(Map<String, dynamic> rep) lire, {
    Duration intervalle = const Duration(seconds: 5),
    Map<String, dynamic>? params,
  }) {
    // L'identité fait partie de la clé : un changement de compte repart
    // d'un sondage neuf (les versions ne se mélangent pas).
    final qui = FirebaseAuth.instance.currentUser?.uid ?? _visiteurId ?? '-';
    final cle = '$qui|$chemin?${params ?? const {}}';
    final sondage = _sondages.putIfAbsent(
        cle, () => _Sondage(this, cle, chemin, params, intervalle));
    return sondage.flux().map(lire);
  }

  /// Force une relecture immédiate d'une ressource sondée (après une
  /// écriture faite par l'app elle-même).
  void rafraichir(String chemin) {
    for (final s in _sondages.values) {
      if (s.chemin == chemin) s.tick();
    }
  }
}

class _Sondage {
  final ApiClient api;
  final String cle;
  final String chemin;
  final Map<String, dynamic>? params;
  final Duration intervalle;

  late final StreamController<Map<String, dynamic>> _ctrl =
      StreamController<Map<String, dynamic>>.broadcast(
    onListen: _demarrer,
    onCancel: _arreterPlusTard,
  );
  Map<String, dynamic>? _dernier;
  String? _version;
  Timer? _minuteur;
  Timer? _arret;
  bool _enCours = false;

  _Sondage(this.api, this.cle, this.chemin, this.params, this.intervalle);

  Stream<Map<String, dynamic>> flux() async* {
    final d = _dernier;
    if (d != null) yield d;
    yield* _ctrl.stream;
  }

  void _demarrer() {
    _arret?.cancel();
    if (_minuteur != null) return;
    tick();
    _minuteur = Timer.periodic(intervalle, (_) => tick());
  }

  void _arreterPlusTard() {
    _arret?.cancel();
    _arret = Timer(const Duration(seconds: 3), () {
      if (_ctrl.hasListener) return;
      _minuteur?.cancel();
      _minuteur = null;
      api._sondages.remove(cle);
    });
  }

  Future<void> tick() async {
    if (_enCours) return;
    _enCours = true;
    try {
      final rep = await api.get(chemin, params: {...?params, 'v': _version});
      if (rep is Map<String, dynamic>) {
        if (rep['inchange'] == true) return;
        final v = rep['v'];
        _version = (v is String && v.isNotEmpty) ? v : null;
        _dernier = rep;
        _ctrl.add(rep);
      }
    } catch (e) {
      _ctrl.addError(e);
    } finally {
      _enCours = false;
    }
  }
}

/// Date de l'API (texte ISO 8601), ou ancienne valeur (int ms, DateTime).
DateTime? apiDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is Map && v['seconds'] != null) {
    return DateTime.fromMillisecondsSinceEpoch(
        ((v['seconds'] as num) * 1000).toInt());
  }
  return null;
}

/// Date → texte ISO pour l'API.
String? apiDateTexte(DateTime? d) => d?.toUtc().toIso8601String();

/// Document renvoyé par l'API (même forme d'usage qu'un document Firestore :
/// `doc.id`, `doc.data()`), pour les écrans qui lisent des données brutes.
class Doc {
  final String id;
  final Map<String, dynamic> _donnees;

  Doc(this.id, this._donnees);

  factory Doc.depuis(Map<String, dynamic> m) =>
      Doc('${m['id'] ?? m['reference'] ?? m['token'] ?? ''}', m);

  Map<String, dynamic> data() => _donnees;

  dynamic operator [](String cle) => _donnees[cle];

  static List<Doc> liste(dynamic rep) =>
      ApiClient.items(rep).map(Doc.depuis).toList();
}
