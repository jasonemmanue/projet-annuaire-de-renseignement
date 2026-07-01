import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/messagerie_service.dart';
import '../services/analytics_service.dart';
import '../services/favoris_service.dart'; // ← ÉTAPE 1
import '../services/paiement_service.dart';
import '../l10n/app_localizations.dart';
import 'messagerie_screen.dart';
import 'urgence_screen.dart';

// ============================================================
// FICHIER : lib/screens/detail_logement_screen.dart
// ============================================================

/// Clé i18n → valeur stockée en français (Firestore)
const _typeBienKeys = <String, String>{
  'Studio': 'type_studio',
  'Appartement': 'type_appartement',
  'Villa': 'type_villa',
  'Terrain': 'type_terrain',
  'Bureau': 'type_bureau',
  'Commerce': 'type_commerce',
  'Pharmacie': 'type_pharmacie',
  'Restaurant / Snack': 'type_restaurant',
  'Entreprise': 'type_entreprise',
};

const _equipKeys = <String, String>{
  'Meublé': 'equip_meuble',
  'Wifi': 'equip_wifi',
  'Climatiseur': 'equip_clim',
  'Eau chaude': 'equip_eau',
  'Gardien': 'equip_gardien',
  'Parking': 'equip_parking',
  'Groupe électrogène': 'equip_groupe',
  'Titre foncier': 'equip_titre',
};

class DetailLogementScreen extends StatefulWidget {
  final Logement logement;
  const DetailLogementScreen({super.key, required this.logement});

  @override
  State<DetailLogementScreen> createState() => _DetailLogementScreenState();
}

// ÉTAPE 5 — SingleTickerProviderStateMixin ajouté
class _DetailLogementScreenState extends State<DetailLogementScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPhoto = 0;
  bool _contactLoading = false;

  // ── État signalement ────────────────────────────────────────
  bool _dejaSignale = false;

  // ── Accès prioritaire (urgence 48 H) ────────────────────────
  bool _aUrgence = false;        // le visiteur a payé l'accès
  bool _estProprietaire = false; // c'est sa propre annonce

  // ── Fallback : infos prestataire chargées depuis /users si les champs
  //    prestatireNom / prestatirePhone / prestatirePhoto sont vides dans
  //    le logement (ancien logement créé avant qu'on remplisse ces champs).
  String? _extraNom;
  String? _extraPhone;
  String? _extraPhoto;

  // ─── Favoris ────────────────────────────────────────────────────────────
  // ÉTAPE 3 — champs favoris
  final _favorisService = FavorisService.instance;
  bool _estFavori = false;
  bool _favoriChargement = true;

  // ─── Animation cœur ─────────────────────────────────────────────────────
  // ÉTAPE 3 — contrôleur et animation
  late final AnimationController _heartController;
  late final Animation<double> _heartScale;

  late AppLocalizations _loc;

  Logement get l => widget.logement;

  // Clé SharedPreferences : "signalement_<logementId>"
  String get _prefKey => 'signalement_${l.id}';

  @override
  void initState() {
    super.initState();
    _incrementerVues();
    _chargerEtatSignalement();
    _verifierAccesUrgence();
    _chargerInfosPrestataireExtra();
    // [ANALYTICS] Vue logement — event GA4 "view_item"
    AnalyticsService.instance.logVueLogement(
      l.id,
      l.titre,
      l.ville,
      l.prix.toDouble(),
    );

    // ÉTAPE 3 — Contrôleur animation cœur (100 ms aller, 100 ms retour)
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_heartController);

    // Chargement de l'état favori
    _loadFavoriState();

  }

  Future<void> _quitterAvecPub() async {
    if (mounted) Navigator.pop(context);
  }

  /// Vérifie si ce logement a déjà été signalé par cet appareil
  Future<void> _chargerEtatSignalement() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _dejaSignale = prefs.getBool(_prefKey) ?? false);
    }
  }

  /// Incrémente le champ `vues` dans Firestore de façon atomique
  Future<void> _incrementerVues() async {
    if (l.id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('logements')
          .doc(l.id)
          .update({'vues': FieldValue.increment(1)});
    } catch (_) {
      // Silencieux — non bloquant
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _heartController.dispose(); // ÉTAPE 3 — dispose animation
    super.dispose();
  }

  // ── FAVORIS ──────────────────────────────────────────────────
  // ÉTAPE 3 — méthodes favoris

  Future<void> _loadFavoriState() async {
    final isFav = await _favorisService.isFavori(widget.logement.id);
    if (mounted) {
      setState(() {
        _estFavori = isFav;
        _favoriChargement = false;
      });
    }
  }

  Future<void> _toggleFavori() async {
    if (_estFavori) {
      // Confirmation avant retrait
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_loc.t('favoris_confirm_remove')),
          content: Text('"${l.titre}"\n${_loc.t('favoris_confirm_remove_body')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_loc.t('common_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(_loc.t('favoris_remove_action')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    _heartController.forward(from: 0);

    final wasAdded = !_estFavori;
    setState(() => _estFavori = wasAdded);

    if (wasAdded) {
      AnalyticsService.instance.logAjoutFavori(l.id);
    }

    try {
      if (wasAdded) {
        await _favorisService.ajouterFavori(widget.logement);
      } else {
        await _favorisService.supprimerFavori(widget.logement.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                wasAdded ? Icons.bookmark_added : Icons.bookmark_remove,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(_loc.t(wasAdded ? 'favoris_added' : 'favoris_removed')),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor:
          wasAdded ? Colors.pinkAccent.shade700 : Colors.grey.shade700,
        ),
      );
    } catch (_) {
      // Rollback optimiste si erreur
      if (mounted) setState(() => _estFavori = !wasAdded);
    }
  }

  // ── SIGNALEMENT ─────────────────────────────────────────────

  /// Affiche la BottomSheet de signalement
  void _ouvrirSignalement() {
    if (_dejaSignale) return; // sécurité double
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SignalementSheet(
        logement: l,
        onSignalementEnvoye: () async {
          // Mémoriser localement que l'annonce a été signalée
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_prefKey, true);
          if (mounted) setState(() => _dejaSignale = true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryLight = context.appPrimaryLight;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: GestureDetector(
              onTap: _quitterAvecPub,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            actions: [
              // ── Bouton favoris avec animation ───────────────
              // ÉTAPE 4 — bouton cœur animé (remplace l'ancien GestureDetector statique)
              if (_favoriChargement)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ScaleTransition(
                  scale: _heartScale,
                  child: GestureDetector(
                    onTap: _toggleFavori,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) => ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                          child: Icon(
                            _estFavori ? Icons.bookmark : Icons.bookmark_border,
                            key: ValueKey(_estFavori),
                            color: _estFavori ? AppColors.accent : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // ── Bouton partager ─────────────────────────────
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
              // ── Bouton "..." avec menu Signaler ─────────────
              PopupMenuButton<String>(
                icon: Container(
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_vert, color: Colors.white),
                  ),
                ),
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'signaler',
                    child: Row(
                      children: [
                        Icon(
                          _dejaSignale ? Icons.flag : Icons.flag_outlined,
                          size: 18,
                          color: _dejaSignale ? AppColors.textHint : AppColors.error,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _dejaSignale ? _loc.t('detail_already_reported_short') : _loc.t('detail_report'),
                          style: TextStyle(
                            color: _dejaSignale ? AppColors.textHint : context.appTextPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'signaler' && !_dejaSignale) {
                    _ouvrirSignalement();
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: l.photos.isEmpty ? 1 : l.photos.length,
                    onPageChanged: (i) => setState(() => _currentPhoto = i),
                    itemBuilder: (_, i) => l.photos.isEmpty
                        ? Container(
                      color: primaryLight,
                      child: const Icon(Icons.home, size: 80, color: AppColors.primary),
                    )
                        : InteractiveViewer(
                      child: Image.network(
                        l.photos[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: primaryLight,
                          child: const Icon(Icons.home, size: 80, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                  if (l.photos.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          l.photos.length,
                              (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _currentPhoto == i ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _currentPhoto == i ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentPhoto + 1}/${l.photos.isEmpty ? 1 : l.photos.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 80,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black45, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // EN-TETE
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Text(l.titre, style: AppTextStyles.h2)),
                          if (l.estVerifie)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(children: [
                                const Icon(Icons.verified, color: AppColors.primary, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _loc.t('detail_verified'),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ]),
                            ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.location_on, size: 16, color: context.appTextSecondary),
                          const SizedBox(width: 4),
                          Text('${l.quartier}, ${l.ville}', style: AppTextStyles.bodyMedium),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: l.typeLocation == 'location'
                                  ? primaryLight
                                  : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              l.typeLocation == 'location' ? _loc.t('detail_for_rent') : _loc.t('detail_for_sale'),
                              style: TextStyle(
                                color: l.typeLocation == 'location'
                                    ? AppColors.primary
                                    : AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(l.prixLabel, style: AppTextStyles.price.copyWith(fontSize: 24)),
                          Row(children: [
                            Icon(Icons.remove_red_eye_outlined,
                                size: 14, color: context.appTextSecondary),
                            const SizedBox(width: 4),
                            Text('${l.nbVues} ${_loc.t('detail_views')}', style: AppTextStyles.caption),
                          ]),
                        ]),
                      ],
                    ),
                  ),
                  const Divider(),

                  // CARACTERISTIQUES
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _CaracItem(icon: Icons.straighten, label: '${l.surface} m²', sublabel: _loc.t('detail_surface')),
                        _CaracItem(icon: Icons.king_bed_outlined, label: '${l.nbPieces}', sublabel: _loc.t('detail_rooms')),
                        _CaracItem(icon: Icons.category_outlined, label: _loc.t(_typeBienKeys[l.typeBien] ?? l.typeBien), sublabel: _loc.t('detail_type')),
                        _CaracItem(
                          icon: l.disponible ? Icons.check_circle_outline : Icons.cancel_outlined,
                          label: l.disponible ? _loc.t('detail_available') : _loc.t('detail_unavailable'),
                          sublabel: _loc.t('detail_status_label'),
                          color: l.disponible ? AppColors.success : AppColors.error,
                        ),
                      ],
                    ),
                  ),

                  // ── Horaires pharmacie / restaurant ───────────
                  if ((l.typeBien == 'Pharmacie' || l.typeBien == 'Restaurant / Snack') &&
                      l.heureOuverture != null && l.heureFermeture != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: l.estOuvertMaintenant
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: l.estOuvertMaintenant
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(children: [
                          Icon(
                            l.estOuvertMaintenant
                                ? Icons.storefront
                                : Icons.store_mall_directory_outlined,
                            color: l.estOuvertMaintenant
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.estOuvertMaintenant ? _loc.t('detail_open_now') : _loc.t('detail_closed'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: l.estOuvertMaintenant
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                              Text(
                                '${l.heureOuverture} – ${l.heureFermeture}',
                                style: TextStyle(
                                    fontSize: 12, color: context.appTextSecondary),
                              ),
                            ],
                          )),
                        ]),
                      ),
                    ),

                  const Divider(),

                  // DESCRIPTION
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_loc.t('detail_description'), style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      _ExpandableText(text: l.description),
                    ]),
                  ),
                  const Divider(),

                  // EQUIPEMENTS
                  if (l.equipements.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_loc.t('detail_equipment'), style: AppTextStyles.h3),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: l.equipements.map((e) => _EquipementChip(label: e)).toList(),
                        ),
                      ]),
                    ),
                    const Divider(),
                  ],

                  // CARTE GOOGLE MAPS
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_loc.t('detail_location'), style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('${l.quartier}, ${l.ville}', style: AppTextStyles.bodyMedium),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: '${l.latitude}, ${l.longitude}'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_loc.t('detail_coords_copied')),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Row(children: [
                            Icon(Icons.copy, size: 13, color: context.appTextSecondary),
                            const SizedBox(width: 3),
                            Text(_loc.t('detail_copy_gps'),
                                style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 8),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 200,
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(l.latitude, l.longitude),
                              zoom: 15,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('logement'),
                                position: LatLng(l.latitude, l.longitude),
                                infoWindow: InfoWindow(
                                  title: l.titre,
                                  snippet: '${l.quartier}, ${l.ville}',
                                ),
                              ),
                            },
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                            scrollGesturesEnabled: true,
                            zoomGesturesEnabled: true,
                            rotateGesturesEnabled: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Lat: ${l.latitude.toStringAsFixed(5)} · Lng: ${l.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                      ),
                    ]),
                  ),
                  const Divider(),

                  // PRESTATAIRE
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_loc.t('detail_provider'), style: AppTextStyles.h3),
                      const SizedBox(height: 12),
                      Row(children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: primaryLight,
                          backgroundImage: _prestatirePhotoAffiche != null
                              ? NetworkImage(_prestatirePhotoAffiche!)
                              : null,
                          child: _prestatirePhotoAffiche == null
                              ? Text(
                            _prestataireNomAffiche.isNotEmpty
                                ? _prestataireNomAffiche[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                          )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(
                                child: Text(
                                  _prestataireNomAffiche.isNotEmpty
                                      ? _prestataireNomAffiche
                                      : _loc.t('detail_provider'),
                                  style: AppTextStyles.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (l.estVerifie) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, color: AppColors.primary, size: 16),
                              ],
                            ]),
                            Text(
                              (_aUrgence || _estProprietaire)
                                  ? (_prestatirePhoneAffiche.isNotEmpty
                                      ? _prestatirePhoneAffiche
                                      : _loc.t('detail_phone_missing'))
                                  : _loc.t('detail_phone_masked'),
                              style: AppTextStyles.bodyMedium,
                            ),
                          ]),
                        ),
                        if ((_aUrgence || _estProprietaire) &&
                            _prestatirePhoneAffiche.isNotEmpty)
                          IconButton(
                            onPressed: _appelerPrestataire,
                            icon: const Icon(Icons.phone, color: AppColors.primary),
                            style: IconButton.styleFrom(
                              backgroundColor: primaryLight,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                      ]),
                      // ── Réserver une table (Restaurant / Snack) ──
                      if (l.typeBien == 'Restaurant / Snack') ...[
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _contactLoading ? null : _contacterPrestataire,
                          icon: _contactLoading
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.table_restaurant, size: 18),
                          label: Text(_loc.t('detail_reserve_table')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],

                      // ── Accès prioritaire 48 H (si contact masqué) ──
                      if (!_aUrgence && !_estProprietaire && l.typeBien != 'Pharmacie') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.bolt, color: Colors.red.shade700, size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _loc.t('detail_priority_desc'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.red.shade900,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: _ouvrirUrgence,
                                icon: const Icon(Icons.flash_on, size: 18),
                                label: Text(_loc.t('detail_unlock_priority')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ]),
                  ),

                  if (l.documentPdf != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (l.documentPdf == null) return;
                          final uri = Uri.parse(l.documentPdf!);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf, color: AppColors.error),
                        label: Text(_loc.t('detail_view_pdf')),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44)),
                      ),
                    ),

                  // ── Lien discret "Signaler cette annonce" ─────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Center(
                      child: GestureDetector(
                        onTap: _dejaSignale ? null : _ouvrirSignalement,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dejaSignale ? Icons.flag : Icons.flag_outlined,
                              size: 13,
                              color: _dejaSignale
                                  ? AppColors.textHint
                                  : context.appTextSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _dejaSignale
                                  ? _loc.t('detail_already_reported')
                                  : _loc.t('detail_report'),
                              style: TextStyle(
                                fontSize: 12,
                                color: _dejaSignale
                                    ? AppColors.textHint
                                    : context.appTextSecondary,
                                decoration: _dejaSignale
                                    ? TextDecoration.none
                                    : TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: _partager,
            icon: const Icon(Icons.share),
            label: Text(_loc.t('detail_share')),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _contactLoading ? null : _contacterPrestataire,
              icon: _contactLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.chat_bubble_outline),
              label: Text(_loc.t('detail_contact_owner')),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _contacterPrestataire() async {
    // #26 — Avertir si annonce non vérifiée
    if (!l.estVerifie) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            Flexible(child: Text(_loc.t('detail_unverified_title'))),
          ]),
          content: Text(_loc.t('detail_unverified_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_loc.t('detail_unverified_cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(_loc.t('detail_unverified_continue')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    setState(() => _contactLoading = true);
    try {
      final auth = AuthService.instance;
      final currentUid = auth.isLoggedIn
          ? auth.currentUser!.id
          : await getOrCreateVisitorId();

      if (currentUid == l.prestatireId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_loc.t('detail_cannot_contact_own')),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      final conversationId = await MessagerieService.getOrCreateConversation(
        clientId: currentUid,
        prestataireId: l.prestatireId,
        logementId: l.id,
        logementTitre: l.titre,
        logementPhoto: l.photos.isNotEmpty ? l.photos.first : null,
      );
      if (!mounted) return;

      final myUids = await getAllMyUids();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            logementTitre: l.titre,
            logementPhoto: l.photos.isNotEmpty ? l.photos.first : null,
            otherId: l.prestatireId,
            currentUid: currentUid,
            myUids: myUids,
            isOtherVisitor: false,
            isCurrentUserPrestataire: auth.isLoggedIn,
            logementId: l.id, // [ANALYTICS] nouveau
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_loc.t('detail_msg_error')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    } finally {
      if (mounted) setState(() => _contactLoading = false);
    }
  }

  void _partager() {
    HapticFeedback.lightImpact();
    // [ANALYTICS] Partage annonce
    AnalyticsService.instance.logPartageAnnonce(l.id);
    final texte = '${l.titre}\n${l.quartier}, ${l.ville}\n${l.prixLabel}\n\n'
        'Découvrez cette annonce sur Horem+.';
    Share.share(texte, subject: 'Annonce Horem+ – ${l.titre}');
  }

  void _appelerPrestataire() async {
    final tel = _prestatirePhoneAffiche;
    if (tel.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: tel.replaceAll(' ', ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_loc.t('detail_cannot_call')} $tel'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Fallback : va chercher nom/tel/photo dans /users si absents du logement ─
  Future<void> _chargerInfosPrestataireExtra() async {
    // Rien à charger si tout est déjà présent dans le logement
    if (l.prestatireNom.isNotEmpty &&
        l.prestatirePhone.isNotEmpty &&
        (l.prestatirePhoto?.isNotEmpty ?? false)) {
      return;
    }
    if (l.prestatireId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(l.prestatireId)
          .get();
      final data = snap.data();
      if (data == null || !mounted) return;
      final prenom = (data['prenom'] as String?)?.trim() ?? '';
      final nom = (data['nom'] as String?)?.trim() ?? '';
      final nomComplet = ('$prenom $nom').trim();
      setState(() {
        if (l.prestatireNom.isEmpty && nomComplet.isNotEmpty) {
          _extraNom = nomComplet;
        }
        if (l.prestatirePhone.isEmpty) {
          _extraPhone = (data['telephone'] as String?)?.trim();
        }
        if ((l.prestatirePhoto?.isEmpty ?? true)) {
          _extraPhoto = (data['photoUrl'] as String?)?.trim();
        }
      });
    } catch (_) {
      // silencieux — les champs par défaut du logement seront utilisés
    }
  }

  // Getters unifiés : préfèrent la valeur du logement, sinon celle du user.
  String get _prestataireNomAffiche =>
      l.prestatireNom.isNotEmpty ? l.prestatireNom : (_extraNom ?? '');
  String get _prestatirePhoneAffiche =>
      l.prestatirePhone.isNotEmpty ? l.prestatirePhone : (_extraPhone ?? '');
  String? get _prestatirePhotoAffiche {
    if (l.prestatirePhoto != null && l.prestatirePhoto!.isNotEmpty) {
      return l.prestatirePhoto;
    }
    if (_extraPhoto != null && _extraPhoto!.isNotEmpty) return _extraPhoto;
    return null;
  }

  // ── Accès prioritaire (urgence 48 H) ──────────────────────────────────────
  Future<void> _verifierAccesUrgence() async {
    final uid = AuthService.instance.currentUser?.id;
    final estProp = uid != null && uid == l.prestatireId;
    // Pour les pharmacies (et autres services gratuits), l'accès est toujours accordé
    final isServiceGratuit = l.typeBien == 'Pharmacie';
    final aAcces = estProp || isServiceGratuit ||
        await PaiementService.instance.aAccesUrgence(l.id);
    if (!mounted) return;
    setState(() {
      _estProprietaire = estProp;
      _aUrgence = aAcces;
    });
  }

  Future<void> _ouvrirUrgence() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => UrgenceScreen(logement: l)),
    );
    if (ok == true) _verifierAccesUrgence();
  }
}

// ============================================================
// WIDGET INTERNE : BottomSheet de signalement
// ============================================================

class _SignalementSheet extends StatefulWidget {
  final Logement logement;
  final VoidCallback onSignalementEnvoye;

  const _SignalementSheet({
    required this.logement,
    required this.onSignalementEnvoye,
  });

  @override
  State<_SignalementSheet> createState() => _SignalementSheetState();
}

class _SignalementSheetState extends State<_SignalementSheet> {
  // Internal keys kept in French — only labels are translated
  static const List<String> _motifs = [
    'Prix incorrect ou trompeur',
    'Logement inexistant ou inaccessible',
    'Photos non conformes à la réalité',
    'Contenu inapproprié ou offensant',
    'Annonce dupliquée',
    'Autre (préciser)',
  ];

  late AppLocalizations _loc;
  String? _motifSelectionne;
  final TextEditingController _autreController = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  bool get _estAutre => _motifSelectionne == _motifs.last;

  List<String> get _motifLabels => [
    _loc.t('detail_report_wrong_price'),
    _loc.t('detail_report_nonexistent'),
    _loc.t('detail_report_wrong_photos'),
    _loc.t('detail_report_inappropriate'),
    _loc.t('detail_report_duplicate'),
    _loc.t('detail_report_other'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }
  bool get _peutEnvoyer =>
      _motifSelectionne != null &&
          (_estAutre ? _autreController.text.trim().isNotEmpty : true) &&
          !_envoi;

  @override
  void dispose() {
    _autreController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!_peutEnvoyer) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });

    try {
      final auth = AuthService.instance;
      final String signalePar;
      final String signaleParType;

      if (auth.isLoggedIn) {
        signalePar = auth.currentUser!.id;
        signaleParType = 'prestataire';
      } else {
        signalePar = await getOrCreateVisitorId();
        signaleParType = 'visiteur';
      }

      final signalement = SignalementModel(
        logementId: widget.logement.id,
        logementTitre: widget.logement.titre,
        motif: _motifSelectionne!,
        motifLibre: _estAutre ? _autreController.text.trim() : null,
        signalePar: signalePar,
        signaleParType: signaleParType,
        dateSignalement: DateTime.now(),
        statut: 'en_attente',
      );

      await FirebaseFirestore.instance
          .collection('signalements')
          .add(signalement.toMap());

      widget.onSignalementEnvoye();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(_loc.t('detail_report_success')),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = _loc.t('common_error_retry');
        _envoi = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Poignée ──
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Titre ──
          Row(children: [
            const Icon(Icons.flag_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Text(
              _loc.t('detail_report'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, size: 20, color: context.appTextSecondary),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            _loc.t('detail_report_subtitle'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // ── Liste des motifs ──
          ...List.generate(_motifs.length, (i) {
            final motif = _motifs[i];
            final label = _motifLabels[i];
            final selected = _motifSelectionne == motif;
            return InkWell(
              onTap: () => setState(() {
                _motifSelectionne = motif;
                _erreur = null;
              }),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? context.appPrimaryLight : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppColors.primary : Colors.grey.shade200,
                    width: selected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Radio<String>(
                    value: motif,
                    groupValue: _motifSelectionne,
                    onChanged: (v) => setState(() {
                      _motifSelectionne = v;
                      _erreur = null;
                    }),
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? AppColors.primary
                            : context.appTextPrimary,
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),

          // ── Champ texte libre si "Autre" ──
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _estAutre
                ? Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: TextField(
                controller: _autreController,
                autofocus: true,
                maxLines: 3,
                maxLength: 300,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _loc.t('detail_report_placeholder'),
                  hintStyle:
                  TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            )
                : const SizedBox.shrink(),
          ),

          // ── Message d'erreur ──
          if (_erreur != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _erreur!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),

          // ── Bouton envoyer ──
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _peutEnvoyer ? _envoyer : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.grey.shade200,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _envoi
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Text(
                _loc.t('detail_report_send'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGETS RÉUTILISABLES
// ============================================================

class _CaracItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color? color;
  const _CaracItem(
      {required this.icon, required this.label, required this.sublabel, this.color});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color ?? AppColors.primary, size: 24),
      const SizedBox(height: 4),
      Text(label,
          style: AppTextStyles.bodyLarge
              .copyWith(fontWeight: FontWeight.w700, color: color)),
      Text(sublabel, style: AppTextStyles.caption),
    ],
  );
}

class _EquipementChip extends StatelessWidget {
  final String label;
  const _EquipementChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: context.appPrimaryLight, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(l.t(_equipKeys[label] ?? label),
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

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
        overflow:
        _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      ),
      if (widget.text.length > 200)
        Builder(
          builder: (context) {
            final loc = AppLocalizations.of(context);
            return GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expanded ? loc.t('detail_see_less') : loc.t('detail_see_more'),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
        ),
    ],
  );
}