// ============================================================
// FICHIER : lib/services/tarification_service.dart
// Encode les grilles de prix actives :
//
//  ① Publication standard — 3 % du prix du bien
//  ② Hébergement          — forfait par durée (Meublé/Motel, Auberge, Hôtel)
//  ③ Urgence visiteur     — 200 XAF / 48 h
//  ④ Sponsoring           — forfait par durée (1 sem / 2 sem / 1 mois)
//  ⑤ Visibilité annuelle  — forfait par type de service
//
// L'ancienne grille de commission variable par GRADE (enum GradeBien,
// pourcentageCommission, montantSponsorisation, fraisUrgence) a été retirée :
// plus aucun appelant depuis le passage aux forfaits fixes.
//
// ⚠️ PLANCHER PAIEMENT : tout paiement de 100/150 est porté à 200
//    (consigne client + montant minimum agrégateur).
//
// Devise : XAF (Cameroun).
// ============================================================

/// Devise de l'application.
const String kDevise = 'XAF';

/// Plancher du montant d'une transaction (consigne : 100/150 → 200).
const int kMinPaiement = 200;

class TarificationService {
  TarificationService._();
  static final TarificationService instance = TarificationService._();

  /// Applique le plancher (≥ 200).
  static int minMontant(num montant) {
    final m = montant.round();
    return m < kMinPaiement ? kMinPaiement : m;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ① COMMISSION FIXE 3 % — biens immobiliers standards
  // ═══════════════════════════════════════════════════════════════════════════
  /// Taux de commission unique appliqué à Studio, Appartement, Villa, Terrain,
  /// Bureau, Commerce et « Autre ». Publication visible 1 mois.
  static const double commissionStandard = 0.03;

  /// Montant à payer pour publier un bien standard (3 % du prix, plancher 200).
  static int montantPublicationStandard(double prixBien) {
    return minMontant(prixBien * commissionStandard);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ② HÉBERGEMENT — forfait par durée (Meublé/Motel, Auberge, Hôtel)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Grille hébergement : type → { code durée → prix XAF }.
  static const Map<String, Map<String, int>> tarifsHebergement = {
    'Meublé / Motel': {'1m': 2000, '3m': 5000, '6m': 10000, '1a': 20000},
    'Auberge':        {'1m': 1000, '3m': 3000, '6m': 5000,  '1a': 10000},
    'Hôtel':          {'1m': 3000, '3m': 8000, '6m': 15000, '1a': 25000},
  };

  /// Durée (en jours) associée à chaque code de forfait.
  static const Map<String, int> dureeJoursHebergement = {
    '1m': 30,
    '3m': 90,
    '6m': 180,
    '1a': 365,
  };

  /// Options affichables dans un sélecteur de durée pour l'hébergement.
  static const List<({String code, String label, int jours})>
      optionsHebergement = [
    (code: '1m', label: '1 mois',  jours: 30),
    (code: '3m', label: '3 mois',  jours: 90),
    (code: '6m', label: '6 mois',  jours: 180),
    (code: '1a', label: '1 an',    jours: 365),
  ];

  /// Types éligibles au forfait hébergement (clés de la grille).
  static const List<String> typesHebergement = [
    'Meublé / Motel',
    'Auberge',
    'Hôtel',
  ];

  /// Vrai si [typeBien] utilise la grille forfaitaire (hébergement).
  static bool isTypeHebergement(String typeBien) =>
      tarifsHebergement.containsKey(typeBien);

  /// Montant hébergement (XAF) pour un type + code durée ('1m'|'3m'|'6m'|'1a').
  /// Retourne null si le type ou la durée n'est pas dans la grille.
  static int? montantHebergement(String typeBien, String codeDuree) {
    return tarifsHebergement[typeBien]?[codeDuree];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ③ VISITEUR — urgence (traitement prioritaire), montant fixe
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Grille « CÔTÉ CLIENTS — URGENCES » (valeurs brutes, avant plancher 200) :
  //   STANDARD     : chambres 100 · studios 100 · appartements 150
  //   HAUT STANDING: chambres 150 · studios 150 · appartements 200
  //   MEUBLÉS      : chambres standards 150 · chambres meublés 200
  //                  studios meublés 300 · appartements meublés 500
  //   Auberges 100 · Magasins/Boutiques 100 · Motels & Hôtels 1★ 100
  //   Hôtels 2-3★ 200 · Hôtels 4-5★ 500
  //
  // ⚠️ Plancher 200 appliqué : tous les 100 et 150 deviennent 200.

  // ═══════════════════════════════════════════════════════════════════════════
  // ④ SPONSORING IMMOBILIER — tarif fixe par durée
  // ═══════════════════════════════════════════════════════════════════════════
  static const Map<String, int> tarifsSponsoring = {
    '1s': 500,   // 1 semaine
    '2s': 1000,  // 2 semaines
    '1m': 2000,  // 1 mois
  };

  static const Map<String, int> dureeJoursSponsoring = {
    '1s': 7,
    '2s': 14,
    '1m': 30,
  };

  static const List<({String code, String label, int prix, int jours})>
      optionsSponsoring = [
    (code: '1s', label: '1 semaine', prix: 500, jours: 7),
    (code: '2s', label: '2 semaines', prix: 1000, jours: 14),
    (code: '1m', label: '1 mois', prix: 2000, jours: 30),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // ⑤ VISIBILITÉ ANNUELLE — tarif fixe par type de service
  // ═══════════════════════════════════════════════════════════════════════════
  static const Duration dureeVisibilite = Duration(days: 365);

  static const Map<String, int> _tarifsVisibilite = {
    'entreprise': 3000,
    'restaurant / snack': 2000,
    'école': 1000,
  };

  /// Types éligibles à la visibilité annuelle (clés en minuscules).
  static const List<String> typesVisibilite = [
    'Entreprise',
    'Restaurant / Snack',
    'École',
  ];

  /// Montant de la visibilité annuelle selon le type de bien (insensible à la casse).
  static int montantVisibilite(String typeBien) {
    final key = typeBien.toLowerCase();
    return _tarifsVisibilite[key] ?? 2000;
  }

  /// Durée d'accès accordée au visiteur après paiement de l'urgence.
  static const Duration dureeUrgence = Duration(hours: 48);
}
