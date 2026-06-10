// ============================================================
// FICHIER : lib/services/tarification_service.dart
// Encode la grille de prix « DEVIS IMMO » :
//
//  ① CÔTÉ PRESTATAIRE — commission sponsorisation = % du prix du bien
//     selon le GRADE (standards 3 %, haut standing 5 %, meublés 3–5 %,
//     à louer 3 %).
//
//  ② CÔTÉ VISITEUR — frais d'URGENCE (traitement prioritaire) = montant
//     fixe selon type + grade.
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

/// Grades de standing d'un bien.
enum GradeBien { standards, hautStanding, meubles, aLouer }

extension GradeBienLabel on GradeBien {
  String get label {
    switch (this) {
      case GradeBien.standards:
        return 'Standard';
      case GradeBien.hautStanding:
        return 'Haut standing';
      case GradeBien.meubles:
        return 'Meublé';
      case GradeBien.aLouer:
        return 'À louer';
    }
  }

  /// Pour Firestore (champ `grade` du logement).
  String get code {
    switch (this) {
      case GradeBien.standards:
        return 'standards';
      case GradeBien.hautStanding:
        return 'haut_standing';
      case GradeBien.meubles:
        return 'meubles';
      case GradeBien.aLouer:
        return 'a_louer';
    }
  }

  static GradeBien fromCode(String? code) {
    switch (code) {
      case 'haut_standing':
        return GradeBien.hautStanding;
      case 'meubles':
        return GradeBien.meubles;
      case 'a_louer':
        return GradeBien.aLouer;
      default:
        return GradeBien.standards;
    }
  }
}

class TarificationService {
  TarificationService._();
  static final TarificationService instance = TarificationService._();

  /// Applique le plancher (≥ 200).
  static int minMontant(num montant) {
    final m = montant.round();
    return m < kMinPaiement ? kMinPaiement : m;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ① PRESTATAIRE — commission sponsorisation (% du prix du bien)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Grille « REVENUS EN POURCENTAGE DU MONTANT À LOUER » :
  //   STANDARDS (chambres, studios, appartements)        → 3 %
  //   HAUT STANDING (chambres, studios, appartements)    → 5 %
  //   MEUBLÉS : auberges 3 % · motels/meublés 3,5 %
  //             hôtels 1★ 3,5 % · hôtels 2-3★ 4 % · hôtels 4-5★ 5 %
  //   À LOUER (boutiques, espaces, terrains)             → 3 %

  /// Pourcentage de commission selon grade + type de bien.
  /// [typeBien] : 'Studio','Appartement','Villa','Chambre','Auberge',
  ///              'Hotel1','Hotel23','Hotel45','Boutique','Espace','Terrain'…
  double pourcentageCommission(GradeBien grade, String typeBien) {
    final t = typeBien.toLowerCase();
    switch (grade) {
      case GradeBien.standards:
        return 0.03; // 3 %
      case GradeBien.hautStanding:
        return 0.05; // 5 %
      case GradeBien.aLouer:
        return 0.03; // boutiques / espaces / terrains → 3 %
      case GradeBien.meubles:
        if (t.contains('auberge')) return 0.03;
        if (t.contains('motel') || t.contains('meubl')) return 0.035;
        if (t.contains('1') || t.contains('etoile1')) return 0.035; // 1★
        if (t.contains('23') || t.contains('2') || t.contains('3')) return 0.04; // 2-3★
        if (t.contains('45') || t.contains('4') || t.contains('5')) return 0.05; // 4-5★
        return 0.035; // défaut meublés
    }
  }

  /// Montant de la sponsorisation = % du prix du bien, planché à 200 XOF.
  int montantSponsorisation({
    required GradeBien grade,
    required String typeBien,
    required double prixBien,
  }) {
    final pct = pourcentageCommission(grade, typeBien);
    return minMontant(prixBien * pct);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ② VISITEUR — frais d'urgence (traitement prioritaire), montant fixe
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

  /// Durée d'accès accordée au visiteur après paiement de l'urgence.
  static const Duration dureeUrgence = Duration(hours: 48);

  /// Frais d'urgence fixe (XAF) pour un visiteur, selon grade + type.
  int fraisUrgence({required GradeBien grade, required String typeBien}) {
    final t = typeBien.toLowerCase();
    int brut;

    if (grade == GradeBien.meubles) {
      if (t.contains('appartement')) {
        brut = 500;
      } else if (t.contains('studio')) {
        brut = 300;
      } else if (t.contains('chambre')) {
        brut = 200; // chambres meublées haut standing
      } else if (t.contains('auberge') ||
          t.contains('motel') ||
          t.contains('magasin') ||
          t.contains('boutique')) {
        brut = 100;
      } else if (t.contains('45') || t.contains('4') || t.contains('5')) {
        brut = 500; // hôtels 4-5★
      } else if (t.contains('23') || t.contains('2') || t.contains('3')) {
        brut = 200; // hôtels 2-3★
      } else {
        brut = 100; // hôtels 1★ / motels
      }
    } else if (grade == GradeBien.hautStanding) {
      if (t.contains('appartement')) {
        brut = 200;
      } else {
        brut = 150; // chambres / studios
      }
    } else {
      // STANDARD / A LOUER
      if (t.contains('appartement')) {
        brut = 150;
      } else {
        brut = 100; // chambres / studios / autres
      }
    }

    return minMontant(brut); // plancher 200
  }

  /// Libellé lisible du tarif d'urgence (pour l'UI).
  String labelUrgence({required GradeBien grade, required String typeBien}) {
    final f = fraisUrgence(grade: grade, typeBien: typeBien);
    return '$f $kDevise';
  }
}
