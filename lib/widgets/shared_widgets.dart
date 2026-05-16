import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

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
                    child: _buildBadge('Sponsorise', AppColors.accent, Colors.black87),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _buildBadge(
                    logement.typeLocation == 'location' ? 'Location' : 'Vente',
                    logement.typeLocation == 'location'
                        ? AppColors.primary
                        : AppColors.success,
                    Colors.white,
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: _FavoriteButton(logementId: logement.id),
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
                  child: _FavoriteButton(logementId: logement.id, small: true),
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
// BOUTON FAVORI
// ----------------------------------------------------------
class _FavoriteButton extends StatefulWidget {
  final String logementId;
  final bool small;
  const _FavoriteButton({required this.logementId, this.small = false});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _isFavorite = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.small ? 18.0 : 22.0;
    return GestureDetector(
      onTap: () => setState(() => _isFavorite = !_isFavorite),
      child: Container(
        width: widget.small ? 30 : 36,
        height: widget.small ? 30 : 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4),
          ],
        ),
        child: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          color: _isFavorite ? AppColors.error : AppColors.textSecondary,
          size: size,
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
  final VoidCallback? onFilterTap;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: onSearch,
            decoration: InputDecoration(
              hintText: 'Ville, quartier, type de bien...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintStyle: AppTextStyles.bodyMedium,
            ),
          ),
        ),
        if (onFilterTap != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onFilterTap,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tune, color: Colors.white),
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
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
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
              Icon(icon, size: 14, color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
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
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Voir tout',
                  style: TextStyle(
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
// BANDEAU PUBLICITAIRE
// ----------------------------------------------------------
class PubliciteBanner extends StatelessWidget {
  const PubliciteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.campaign_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Publicite', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
                Text(
                  'Votre annonce ici · Contactez-nous',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            child: const Text('En savoir +', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final selectedColor = AppColors.primary;
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Carte',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline),
            activeIcon: Icon(Icons.favorite),
            label: 'Favoris',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
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
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Carte',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite_outline),
          activeIcon: Icon(Icons.favorite),
          label: 'Favoris',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profil',
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