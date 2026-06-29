import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/favoris_service.dart';
import '../services/publicite_service.dart';

// ============================================================
// FICHIER : lib/widgets/shared_widgets.dart
// Composants reutilisables sur tous les ecrans
// ============================================================

// ----------------------------------------------------------
// CARTE LOGEMENT (utilisee en liste et carte)
// ----------------------------------------------------------
class LogementCard extends StatelessWidget {
  final Logement logement;
  final VoidCallback onTap;
  final bool isGrid;

  const LogementCard({
    super.key,
    required this.logement,
    required this.onTap,
    this.isGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isGrid) return _buildGridCard(context);
    return _buildListCard(context);
  }

  Widget _buildListCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image principale
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: logement.photos.isNotEmpty
                      ? Image.network(
                    logement.photos.first,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderImage(180),
                  )
                      : _placeholderImage(180),
                ),
                if (logement.estSponsorie)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _buildBadge(AppLocalizations.of(context).t('common_sponsored'), AppColors.accent, Colors.black87),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _buildBadge(
                    logement.typeLocation == 'location'
                        ? AppLocalizations.of(context).t('filter_rental')
                        : AppLocalizations.of(context).t('filter_sale'),
                    logement.typeLocation == 'location'
                        ? AppColors.primary
                        : AppColors.success,
                    Colors.white,
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: _FavoriteButton(logement: logement),
                ),
              ],
            ),
            // Infos
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre + verifie
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          logement.titre,
                          style: AppTextStyles.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (logement.estVerifie)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.verified, color: AppColors.primary, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Localisation
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      // ✅ CORRIGE : Flexible pour eviter overflow sur texte long
                      Flexible(
                        child: Text(
                          '${logement.quartier}, ${logement.ville}',
                          style: AppTextStyles.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ✅ CORRIGE ligne 130 : Row caracteristiques avec Flexible sur chaque _IconInfo
                  Row(
                    children: [
                      Flexible(
                        child: _IconInfo(
                          icon: Icons.king_bed_outlined,
                          label: '${logement.nbPieces} pieces',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: _IconInfo(
                          icon: Icons.straighten,
                          label: '${logement.surface} m²',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Prix a droite avec Flexible + alignement right
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            logement.prixLabel,
                            style: AppTextStyles.price,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: logement.photos.isNotEmpty
                      ? Image.network(
                    logement.photos.first,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderImage(120),
                  )
                      : _placeholderImage(120),
                ),
                if (logement.estVerifie)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.verified, color: Colors.white, size: 16),
                  ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _FavoriteButton(logement: logement, small: true),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    logement.titre,
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${logement.quartier}, ${logement.ville}',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    logement.prixLabel,
                    style: AppTextStyles.priceSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderImage(double height) => Container(
    height: height,
    width: double.infinity,
    color: AppColors.primaryLight,
    child: const Icon(Icons.home, color: AppColors.primary, size: 48),
  );

  Widget _buildBadge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

// ----------------------------------------------------------
// BOUTON FAVORI (bookmark)
// ----------------------------------------------------------
class _FavoriteButton extends StatefulWidget {
  final Logement logement;
  final bool small;
  const _FavoriteButton({required this.logement, this.small = false});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  final _service = FavorisService.instance;
  bool _isFavorite = false;
  bool _loading = true;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _loadState();
    // Se rafraîchit quand un autre widget ajoute/retire ce logement des favoris
    _sub = FavorisService.onFavoriChanged.listen((_) => _loadState());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    final fav = await _service.isFavori(widget.logement.id);
    if (mounted) setState(() { _isFavorite = fav; _loading = false; });
  }

  Future<void> _onTap() async {
    if (_loading) return;
    final l = AppLocalizations.of(context);
    if (_isFavorite) {
      // Confirmation avant retrait
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.t('favoris_confirm_remove')),
          content: Text('"${widget.logement.titre}"\n${l.t('favoris_confirm_remove_body')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.t('common_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(l.t('favoris_remove_action')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _isFavorite = false);
      await _service.supprimerFavori(widget.logement.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.bookmark_remove, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(l.t('favoris_removed')),
        ]),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      setState(() => _isFavorite = true);
      await _service.ajouterFavori(widget.logement);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.bookmark_added, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(l.t('favoris_added')),
        ]),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.small ? 30.0 : 36.0;
    final iconSize = widget.small ? 16.0 : 20.0;
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: dim,
        height: dim,
        decoration: BoxDecoration(
          color: _isFavorite
              ? AppColors.primary
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
          ],
        ),
        child: _loading
            ? Center(
                child: SizedBox(
                  width: iconSize - 4,
                  height: iconSize - 4,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _isFavorite ? Colors.white : AppColors.primary,
                  ),
                ),
              )
            : Icon(
                _isFavorite ? Icons.bookmark : Icons.bookmark_border,
                color: _isFavorite ? Colors.white : AppColors.textSecondary,
                size: iconSize,
              ),
      ),
    );
  }
}

// ----------------------------------------------------------
// ICONE + LABEL (ex: 3 pieces, 45 m²)
// ----------------------------------------------------------
class _IconInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  const _IconInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min, // ✅ ne prend que l'espace necessaire
    children: [
      Icon(icon, size: 14, color: AppColors.textSecondary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: AppTextStyles.bodyMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

// ----------------------------------------------------------
// BARRE DE RECHERCHE PRINCIPALE
// ----------------------------------------------------------
class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterTap;
  final int filtresActifsCount;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onChanged,
    this.onFilterTap,
    this.filtresActifsCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: onSearch,
            onChanged: onChanged,
            style: TextStyle(color: context.appTextPrimary),
            decoration: InputDecoration(
              hintText: l.t('search_hint'),
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      color: AppColors.textHint,
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                        onSearch('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: context.appSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.appBorder, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintStyle: TextStyle(color: context.appTextHint, fontSize: 14),
            ),
          ),
        ),
        if (onFilterTap != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onFilterTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: filtresActifsCount > 0
                        ? AppColors.primaryDark
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, color: Colors.white),
                ),
                if (filtresActifsCount > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$filtresActifsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------
// CHIP FILTRE RAPIDE
// ----------------------------------------------------------
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : context.appSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : context.appBorder,
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 6)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : context.appTextSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.appTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// SECTION TITRE (avec lien "Voir tout")
// ----------------------------------------------------------
class SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onVoirTout;

  const SectionTitle({super.key, required this.title, this.onVoirTout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ✅ CORRIGE ligne 393 : Flexible pour eviter overflow sur titre long
          Flexible(
            child: Text(
              title,
              style: AppTextStyles.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onVoirTout != null)
            GestureDetector(
              onTap: onVoirTout,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  AppLocalizations.of(context).t('accueil_see_all'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------
// BANDEAU PUBLICITAIRE (AdMob désactivé)
// ----------------------------------------------------------
// Les publicités prestataires sont désormais diffusées via StoriesPublicitesOverlay.
// Ce widget est conservé pour éviter les erreurs de compilation dans les écrans
// qui y font référence, mais il ne rend rien.
class PubliciteBanner extends StatelessWidget {
  final bool? isPremium;
  const PubliciteBanner({super.key, this.isPremium});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ----------------------------------------------------------
// BOTTOM NAVIGATION BAR PRINCIPALE
// ----------------------------------------------------------
class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isPrestataire;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isPrestataire = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    const selectedColor = AppColors.primary;
    final unselectedColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    // ─── Prestataire : 4 onglets (Messages dans le Dashboard) ────
    if (isPrestataire) {
      return BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: bgColor,
        selectedItemColor: selectedColor,
        unselectedItemColor: unselectedColor,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
        elevation: 12,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: l.t('nav_accueil'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.map_outlined),
            activeIcon: const Icon(Icons.map),
            label: l.t('nav_carte'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bookmark_border),
            activeIcon: const Icon(Icons.bookmark),
            label: l.t('nav_favoris'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: l.t('nav_dashboard'),
          ),
        ],
      );
    }

    // ─── Visiteur : 4 onglets (pas de Messages) ───────────────────
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: bgColor,
      selectedItemColor: selectedColor,
      unselectedItemColor: unselectedColor,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
      elevation: 12,
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.home_outlined),
          activeIcon: const Icon(Icons.home),
          label: l.t('nav_accueil'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.map_outlined),
          activeIcon: const Icon(Icons.map),
          label: l.t('nav_carte'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.favorite_outline),
          activeIcon: const Icon(Icons.favorite),
          label: l.t('nav_favoris'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person_outline),
          activeIcon: const Icon(Icons.person),
          label: l.t('nav_profil'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// ETAT VIDE
// ----------------------------------------------------------
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: AppColors.primary),
  );
}

// ----------------------------------------------------------
// Bannière carrousel des publicités prestataires
// Affichée sur l'accueil visiteur au-dessus du fil d'annonces.
// Se cache automatiquement si aucune publicité n'est active.
// ----------------------------------------------------------
class PublicitePrestataireBanner extends StatefulWidget {
  const PublicitePrestataireBanner({super.key});

  @override
  State<PublicitePrestataireBanner> createState() =>
      _PublicitePrestataireBannerState();
}

class _PublicitePrestataireBannerState
    extends State<PublicitePrestataireBanner> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: PubliciteService.getPublicitesActives(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        final pubs = docs
            .map((d) => Publicite.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    l.t('pub_banner_title'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  // Indicateurs de page
                  if (pubs.length > 1)
                    Row(
                      children: List.generate(
                        pubs.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(left: 4),
                          width: i == _currentPage ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: pubs.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _PubCard(pub: pubs[i]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _PubCard extends StatelessWidget {
  final Publicite pub;
  const _PubCard({required this.pub});

  @override
  Widget build(BuildContext context) {
    final hasVideo = pub.videoUrl != null && pub.videoUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            // ── Vignette : photo ou miniature vidéo ──
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(12)),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  pub.photos.isNotEmpty
                      ? Image.network(
                          pub.photos.first,
                          width: 120,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PubPhotoPlaceholder(),
                        )
                      : _PubPhotoPlaceholder(),
                  // Icône play si vidéo disponible
                  if (hasVideo)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 22),
                    ),
                  // Badge "Vidéo" en bas
                  if (hasVideo)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_outlined,
                                color: Colors.white, size: 11),
                            SizedBox(width: 3),
                            Text('Vidéo',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ── Textes ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(pub.titre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(pub.description,
                        style: TextStyle(
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7),
                            fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    // Nom prestataire
                    Row(children: [
                      const Icon(Icons.person_outline,
                          size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(pub.prestataireNom,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PubPhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 120,
        height: 140,
        color: AppColors.primary.withValues(alpha: 0.12),
        child:
            const Icon(Icons.campaign_outlined, color: AppColors.primary, size: 36),
      );
}