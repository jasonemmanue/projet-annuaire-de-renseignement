import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/favoris_service.dart';
import '../services/messagerie_service.dart';
import '../services/publicite_service.dart';
import '../screens/messagerie_screen.dart';
import 'stories_publicites_overlay.dart';

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
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h3.copyWith(color: Colors.white),
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
                    color: Colors.white70,
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
// BANNIÈRE SERVICES EN VEDETTE — compact strip (72 px)
// Affiche un rectangle cliquable signalant les services actifs.
// Tap → ouvre l'overlay plein-écran StoriesPublicitesOverlay.
// ----------------------------------------------------------
class PublicitePrestataireBanner extends StatefulWidget {
  const PublicitePrestataireBanner({super.key});

  @override
  State<PublicitePrestataireBanner> createState() =>
      _PublicitePrestataireBannerState();
}

class _PublicitePrestataireBannerState
    extends State<PublicitePrestataireBanner> {
  List<Publicite> _pubs = [];
  bool _loaded = false;
  StreamSubscription<List<Publicite>>? _sub;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _autoScrollTimer;
  static const double _tileWidth = 138.0; // 130 + 8 margin

  @override
  void initState() {
    super.initState();
    _sub = PubliciteService.watchPublicitesDiffusables().listen((pubs) {
      if (!mounted) return;
      setState(() {
        _pubs = pubs;
        _loaded = true;
      });
      _demarrerAutoScroll();
    });
  }

  void _demarrerAutoScroll() {
    _autoScrollTimer?.cancel();
    final count = _pubs.length.clamp(0, 6);
    if (count <= 2) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      final current = _scrollCtrl.offset;
      final next = current + _tileWidth;

      if (next >= maxScroll) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      } else {
        _scrollCtrl.animateTo(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _autoScrollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _pubs.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.t('pub_banner_title'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => ouvrirStoriesPublicites(context),
                  child: Text(
                    l.t('pub_banner_see_all'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Previews des publicités (photos + vidéos) — auto-scroll ──
          NotificationListener<ScrollNotification>(
            onNotification: (notif) {
              if (notif is ScrollStartNotification &&
                  notif.dragDetails != null) {
                _autoScrollTimer?.cancel();
              } else if (notif is ScrollEndNotification) {
                _demarrerAutoScroll();
              }
              return false;
            },
            child: SizedBox(
              height: 140,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: List.generate(
                    _pubs.length.clamp(0, 6),
                    (i) => _PubPreviewTile(
                      pub: _pubs[i],
                      onContact: () => _contacterPrestataire(context, _pubs[i]),
                      onTap: () => ouvrirStoriesPublicites(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _contacterPrestataire(BuildContext context, Publicite pub) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid ?? await getOrCreateVisitorId();

    if (currentUid == pub.prestataireId) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('C\'est votre propre publicité.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Utilise l'annonce liée si disponible, sinon fallback sur l'ID pub
    final logementId = pub.logementId ?? 'pub_${pub.id}';
    final logementTitre = pub.logementTitre ?? pub.titre;
    final logementPhoto = pub.logementPhoto
        ?? (pub.photos.isNotEmpty ? pub.photos.first : null);

    final conversationId = await MessagerieService.getOrCreateConversation(
      clientId: currentUid,
      prestataireId: pub.prestataireId,
      logementId: logementId,
      logementTitre: logementTitre.isNotEmpty ? logementTitre : pub.prestataireNom,
      logementPhoto: logementPhoto,
    );
    if (!context.mounted) return;

    final myUids = await getAllMyUids();
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          logementTitre: logementTitre.isNotEmpty ? logementTitre : pub.prestataireNom,
          logementPhoto: logementPhoto,
          otherId: pub.prestataireId,
          currentUid: currentUid,
          myUids: myUids,
          logementId: pub.logementId,
        ),
      ),
    );
  }
}

// ── Tuile de preview pour une publicité (photo ou vidéo) ─────
class _PubPreviewTile extends StatefulWidget {
  final Publicite pub;
  final VoidCallback onContact;
  final VoidCallback onTap;

  const _PubPreviewTile({
    required this.pub,
    required this.onContact,
    required this.onTap,
  });

  @override
  State<_PubPreviewTile> createState() => _PubPreviewTileState();
}

class _PubPreviewTileState extends State<_PubPreviewTile> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    final url = widget.pub.videoUrl;
    if (url != null && url.isNotEmpty) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setVolume(0)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _videoReady = true);
          _videoCtrl!.play();
          _videoCtrl!.setLooping(true);
        }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pub = widget.pub;
    final l = AppLocalizations.of(context);
    final hasVideo = _videoReady && _videoCtrl != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Preview media ──
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                child: hasVideo
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _videoCtrl!.value.size.width,
                              height: _videoCtrl!.value.size.height,
                              child: VideoPlayer(_videoCtrl!),
                            ),
                          ),
                          Positioned(
                            top: 4, left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      )
                    : pub.photos.isNotEmpty
                        ? Image.network(
                            pub.photos.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackIcon(),
                          )
                        : _fallbackIcon(),
              ),
            ),
            // ── Titre + bouton contacter ──
            Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              decoration: const BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pub.titre.isNotEmpty ? pub.titre : pub.prestataireNom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: widget.onContact,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              color: AppColors.primary, size: 10),
                          const SizedBox(width: 3),
                          Text(
                            l.t('pub_banner_contact'),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon() => Container(
        color: Colors.white10,
        child: const Center(
          child: Icon(Icons.campaign_outlined, color: Colors.white54, size: 28),
        ),
      );
}

// ============================================================
// FOND SKYLINE — arrière-plan décoratif pleine page
// ============================================================

class SkylineBackground extends StatelessWidget {
  final Widget child;
  const SkylineBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // ① Gradient pleine page
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF001B3A),
                        const Color(0xFF002A5C),
                        const Color(0xFF001530),
                      ]
                    : [
                        const Color(0xFF002A5C),
                        const Color(0xFF003580),
                        AppColors.primary,
                        const Color(0xFF0088E0),
                      ],
                stops: isDark
                    ? [0.0, 0.4, 1.0]
                    : [0.0, 0.25, 0.6, 1.0],
              ),
            ),
          ),
        ),
        // ② Cercles décoratifs
        Positioned(
          top: -40, right: -30,
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        Positioned(
          top: 200, left: -40,
          child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.03),
            ),
          ),
        ),
        Positioned(
          bottom: 100, right: -20,
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
        ),
        // ③ Skyline en filigrane en bas
        Positioned(
          left: 0, right: 0, bottom: 0,
          height: 120,
          child: CustomPaint(painter: SkylinePainter()),
        ),
        // ④ Contenu
        child,
      ],
    );
  }
}

class SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final buildings = [
      _SkyBat(x: 0,       w: 30, h: 55),
      _SkyBat(x: 28,      w: 22, h: 70),
      _SkyBat(x: 48,      w: 28, h: 45),
      _SkyBat(x: 74,      w: 18, h: 80),
      _SkyBat(x: 90,      w: 35, h: 50),
      _SkyBat(x: 123,     w: 25, h: 65),
      _SkyBat(x: 146,     w: 20, h: 90),
      _SkyBat(x: 164,     w: 30, h: 55),
      _SkyBat(x: 192,     w: 40, h: 42),
      _SkyBat(x: 230,     w: 22, h: 75),
      _SkyBat(x: 250,     w: 28, h: 60),
      _SkyBat(x: 276,     w: 18, h: 85),
      _SkyBat(x: 292,     w: 35, h: 48),
      _SkyBat(x: 325,     w: 25, h: 70),
      _SkyBat(x: 348,     w: 30, h: 55),
      _SkyBat(x: w - 60,  w: 35, h: 65),
      _SkyBat(x: w - 28,  w: 30, h: 48),
    ];

    for (final b in buildings) {
      final top = h - b.h;
      canvas.drawRect(Rect.fromLTWH(b.x, top, b.w, b.h), paint);

      final winPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      const winW = 4.0, winH = 5.0, gap = 7.0;
      int cols = ((b.w - 4) / gap).floor();
      int rows = ((b.h - 10) / gap).floor().clamp(0, 5);
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          canvas.drawRect(
            Rect.fromLTWH(b.x + 4 + c * gap, top + 6 + r * gap, winW, winH),
            winPaint,
          );
        }
      }
    }

    final housePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final houseX = w - 130.0;
    final houseY = h - 80.0;
    canvas.drawRect(Rect.fromLTWH(houseX, houseY, 60, 50), housePaint);
    final roofPath = Path()
      ..moveTo(houseX - 8, houseY)
      ..lineTo(houseX + 30, houseY - 32)
      ..lineTo(houseX + 68, houseY)
      ..close();
    canvas.drawPath(roofPath, housePaint);
    canvas.drawRect(
      Rect.fromLTWH(houseX + 22, houseY + 28, 16, 22),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SkyBat {
  final double x, w, h;
  const _SkyBat({required this.x, required this.w, required this.h});
}