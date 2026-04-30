import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'messagerie_screen.dart';

// ============================================================
// FICHIER : lib/screens/detail_logement_screen.dart
// Écran 4 - Fiche détail logement (§4.1.4)
// Galerie photos, description, caractéristiques, mini-carte,
// boutons Contacter et Partager
// ============================================================

class DetailLogementScreen extends StatefulWidget {
  final Logement logement;

  const DetailLogementScreen({super.key, required this.logement});

  @override
  State<DetailLogementScreen> createState() => _DetailLogementScreenState();
}

class _DetailLogementScreenState extends State<DetailLogementScreen> {
  final PageController _pageController = PageController();
  int _currentPhoto = 0;
  bool _isFavorite = false;

  Logement get l => widget.logement;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ─── GALERIE PHOTOS (§4.1.4 - carrousel, zoom) ────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () => setState(() => _isFavorite = !_isFavorite),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? AppColors.error : Colors.white,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _partager,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.share, color: Colors.white),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Carrousel photos
                  PageView.builder(
                    controller: _pageController,
                    itemCount: l.photos.isEmpty ? 1 : l.photos.length,
                    onPageChanged: (i) => setState(() => _currentPhoto = i),
                    itemBuilder: (_, i) => l.photos.isEmpty
                        ? Container(color: AppColors.primaryLight, child: const Icon(Icons.home, size: 80, color: AppColors.primary))
                        : InteractiveViewer(
                      child: Image.network(
                        l.photos[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primaryLight,
                          child: const Icon(Icons.home, size: 80, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  // Indicateur photo
                  if (l.photos.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(l.photos.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _currentPhoto == i ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _currentPhoto == i ? Colors.white : Colors.white54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )),
                      ),
                    ),
                  // Compteur photos
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '${_currentPhoto + 1}/${l.photos.isEmpty ? 1 : l.photos.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  // Badges
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(height: 80,
                      decoration: const BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.black45, Colors.transparent],
                      )),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── CONTENU PRINCIPAL ──────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── EN-TÊTE : titre, prix, badges ──────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(l.titre, style: AppTextStyles.h2),
                            ),
                            if (l.estVerifie)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.verified, color: AppColors.primary, size: 14),
                                    SizedBox(width: 4),
                                    Text('Vérifié', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text('${l.quartier}, ${l.ville}', style: AppTextStyles.bodyMedium),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: l.typeLocation == 'location' ? AppColors.primaryLight : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l.typeLocation == 'location' ? 'À louer' : 'À vendre',
                                style: TextStyle(
                                  color: l.typeLocation == 'location' ? AppColors.primary : AppColors.success,
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l.prixLabel, style: AppTextStyles.price.copyWith(fontSize: 24)),
                            Row(children: [
                              const Icon(Icons.remove_red_eye_outlined, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text('${l.nbVues} vues', style: AppTextStyles.caption),
                            ]),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(),

                  // ── CARACTÉRISTIQUES RAPIDES ──────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _CaracItem(icon: Icons.straighten, label: '${l.surface} m²', sublabel: 'Surface'),
                        _CaracItem(icon: Icons.king_bed_outlined, label: '${l.nbPieces}', sublabel: 'Pièces'),
                        _CaracItem(icon: Icons.category_outlined, label: l.typeBien, sublabel: 'Type'),
                        _CaracItem(
                          icon: l.disponible ? Icons.check_circle_outline : Icons.cancel_outlined,
                          label: l.disponible ? 'Dispo' : 'Indispo',
                          sublabel: 'Statut',
                          color: l.disponible ? AppColors.success : AppColors.error,
                        ),
                      ],
                    ),
                  ),
                  const Divider(),

                  // ── DESCRIPTION ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Description', style: AppTextStyles.h3),
                        const SizedBox(height: 8),
                        _ExpandableText(text: l.description),
                      ],
                    ),
                  ),
                  const Divider(),

                  // ── ÉQUIPEMENTS ───────────────────────────────
                  if (l.equipements.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Équipements', style: AppTextStyles.h3),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: l.equipements.map((e) => _EquipementChip(label: e)).toList(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                  ],

                  // ── CARTE MINI (§4.1.4) ───────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Localisation', style: AppTextStyles.h3),
                        const SizedBox(height: 8),
                        // Placeholder carte (à remplacer par Google Maps widget)
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.map, size: 60, color: AppColors.primary),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: ElevatedButton.icon(
                                  onPressed: () {/* Ouvrir Google Maps */},
                                  icon: const Icon(Icons.open_in_new, size: 14),
                                  label: const Text('Voir sur la carte', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('${l.quartier}, ${l.ville}', style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                  const Divider(),

                  // ── PROFIL PRESTATAIRE ────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Prestataire', style: AppTextStyles.h3),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primaryLight,
                              backgroundImage: l.prestatirePhoto != null ? NetworkImage(l.prestatirePhoto!) : null,
                              child: l.prestatirePhoto == null
                                  ? Text(l.prestatireNom[0], style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 20))
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(l.prestatireNom, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
                                    if (l.estVerifie) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified, color: AppColors.primary, size: 16),
                                    ],
                                  ]),
                                  Text(l.prestatirePhone, style: AppTextStyles.bodyMedium),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _appelerPrestataire,
                              icon: const Icon(Icons.phone, color: AppColors.primary),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.primaryLight,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── DOCUMENT PDF (si présent - §4.1.4) ───────
                  if (l.documentPdf != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: OutlinedButton.icon(
                        onPressed: () {/* Ouvrir PDF */},
                        icon: const Icon(Icons.picture_as_pdf, color: AppColors.error),
                        label: const Text('Voir le document PDF'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    ),

                  // Espace pour les boutons fixes en bas
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      // ─── BOUTONS FIXES EN BAS ────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(
          children: [
            // Bouton partager (§4.1.4 UC-C07)
            OutlinedButton.icon(
              onPressed: _partager,
              icon: const Icon(Icons.share),
              label: const Text('Partager'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(width: 12),
            // Bouton contacter (§4.1.4 UC-C06)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _contacterPrestataire,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Contacter le propriétaire'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _contacterPrestataire() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: Conversation(
            id: 'conv_${l.id}',
            logementId: l.id,
            logementTitre: l.titre,
            logementPhoto: l.photos.isNotEmpty ? l.photos.first : null,
            prestatireId: l.prestatireId,
            prestatireNom: l.prestatireNom,
            prestatirePhoto: l.prestatirePhoto,
            dernierMessage: null,
            nbNonLus: 0,
            dateDernierMessage: DateTime.now(),
          ),
        ),
      ),
    );
  }

  void _partager() {
    // TODO: Intégrer share_plus (§3.1 UC-C07 - Facebook, WhatsApp, X)
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Partage bientôt disponible (WhatsApp, Facebook, X)'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _appelerPrestataire() {
    // TODO: Intégrer url_launcher pour tel:
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Appeler : ${l.prestatirePhone}'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ----------------------------------------------------------
// ITEM CARACTÉRISTIQUE (surface, pièces, type, statut)
// ----------------------------------------------------------
class _CaracItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color? color;

  const _CaracItem({required this.icon, required this.label, required this.sublabel, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? AppColors.primary, size: 24),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: color)),
        Text(sublabel, style: AppTextStyles.caption),
      ],
    );
  }
}

// ----------------------------------------------------------
// CHIP ÉQUIPEMENT
// ----------------------------------------------------------
class _EquipementChip extends StatelessWidget {
  final String label;
  const _EquipementChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

// ----------------------------------------------------------
// TEXTE EXPANDABLE "Voir plus / Voir moins"
// ----------------------------------------------------------
class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText({required this.text});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.text,
        style: AppTextStyles.bodyMedium,
        maxLines: _expanded ? null : 4,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
      if (widget.text.length > 200)
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _expanded ? 'Voir moins' : 'Voir plus',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
    ],
  );
}