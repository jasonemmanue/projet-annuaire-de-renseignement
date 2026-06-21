import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/logement_service.dart';
import '../services/analytics_service.dart';
import '../services/cache_service.dart';
import '../services/messagerie_service.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart' as sw;
import '../app_controller.dart';
import 'liste_logements_screen.dart';
import 'detail_logement_screen.dart';
import 'messagerie_screen.dart';

// ============================================================
// FICHIER : lib/screens/accueil_screen.dart
// Écran 1 – Page d'accueil / Menu principal
//
// Fonctionnalités :
//   ✅ Chargement Firestore (Future) + fallback cache offline
//   ✅ Bandeau hors-connexion animé avec date du dernier cache
//   ✅ Reconnexion automatique → rechargement Firestore
//   ✅ Pull-to-refresh
//   ✅ Analytics : vue écran + recherche (AnalyticsService)
//   ✅ Sélecteur de langue FR / EN (AppController)
//   ✅ Toggle thème clair / sombre (AppController)
//   ✅ Filtres rapides horizontaux par type de bien
//   ✅ Bottom sheet filtres avancés (prix, type, vérifié)
//   ✅ Carrousel annonces sponsorisées (_SponsoredCard)
//   ✅ Bannières publicitaires intercalées (1 / 5 annonces)
//   ✅ Liste "Recommandés près de vous" avec filtrage local
// ============================================================

class AccueilScreen extends StatefulWidget {
  const AccueilScreen({super.key});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  // ── Données ──────────────────────────────────────────────────
  List<Logement> _logements = [];
  bool _isLoading = true;
  bool _erreurSansCache = false;

  // ── Connectivité & cache ─────────────────────────────────────
  bool _estConnecte = true;
  DateTime? _dateDernierCache;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  // ── Messagerie ───────────────────────────────────────────────
  String? _currentUid;

  // ── Filtres & recherche ──────────────────────────────────────
  String _filtreTypeActif = 'Tous';
  String _texteRecherche  = '';
  FiltreRecherche _filtresAvances = const FiltreRecherche();
  List<String> _suggestions = [];
  final TextEditingController _searchController = TextEditingController();

  // 'value' = valeur interne (correspond à typeBien/typeLocation Firestore, en FR)
  // 'key'   = clé i18n pour l'affichage traduit
  final List<Map<String, dynamic>> _typesBiens = const [
    {'value': 'Tous',        'key': 'type_tous',        'icon': Icons.apps},
    {'value': 'Studio',      'key': 'type_studio',      'icon': Icons.single_bed},
    {'value': 'Appartement', 'key': 'type_appartement', 'icon': Icons.apartment},
    {'value': 'Villa',       'key': 'type_villa',       'icon': Icons.villa},
    {'value': 'Terrain',     'key': 'type_terrain',     'icon': Icons.landscape},
    {'value': 'location',    'key': 'type_location',    'icon': Icons.home_work_outlined},
    {'value': 'vente',       'key': 'type_vente',       'icon': Icons.sell_outlined},
  ];

  late AppLocalizations _l;

  // ── Cycle de vie ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('accueil');
    _initConnectivite();
    _chargerDonnees();
    resolveCurrentUid().then((uid) {
      if (mounted) setState(() => _currentUid = uid);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Connectivité ─────────────────────────────────────────────
  void _initConnectivite() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      final connecte = results.any((r) => r != ConnectivityResult.none);
      if (!mounted) return;
      final etaitDeconnecte = !_estConnecte;
      setState(() => _estConnecte = connecte);
      // Connexion retrouvée → actualiser depuis Firestore
      if (connecte && etaitDeconnecte) {
        await _chargerDepuisFirestore(mettreAJourUI: true);
      }
    });
  }

  Future<bool> _verifierConnexion() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  // ── Chargement des données ───────────────────────────────────
  Future<void> _chargerDonnees() async {
    setState(() {
      _isLoading = true;
      _erreurSansCache = false;
    });
    _estConnecte = await _verifierConnexion();
    if (_estConnecte) {
      await _chargerDepuisFirestore(mettreAJourUI: false);
    } else {
      await _chargerDepuisCache();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Charge depuis Firestore puis met en cache.
  /// [mettreAJourUI] : si true, met aussi _isLoading à false dans cette méthode.
  Future<void> _chargerDepuisFirestore({required bool mettreAJourUI}) async {
    try {
      // Chargement Firestore : retourne Future<List<Logement>>
      final logements = await LogementService.getFutureLogements();
      await CacheService.sauvegarderLogements(logements);
      if (mounted) {
        setState(() {
          _logements = logements;
          _erreurSansCache = false;
          if (mettreAJourUI) _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AccueilScreen] Erreur Firestore : $e');
      // Firestore a échoué → fallback cache
      await _chargerDepuisCache();
    }
  }

  /// Charge depuis le cache local (SharedPreferences via CacheService).
  Future<void> _chargerDepuisCache() async {
    final cached = await CacheService.chargerLogements();
    _dateDernierCache = await CacheService.getCacheDate();
    if (mounted) {
      setState(() {
        if (cached.isNotEmpty) {
          _logements = cached;
          _erreurSansCache = false;
        } else {
          _logements = [];
          _erreurSansCache = true;
        }
      });
    }
  }

  // ── Filtrage local ───────────────────────────────────────────

  // Normalise une chaîne (minuscules + suppression accents)
  static String _n(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâã]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôó]'), 'o')
      .replaceAll(RegExp(r'[ùúû]'), 'u')
      .replaceAll(RegExp(r'ç'), 'c');

  List<Logement> get _logementsFiltres {
    var result = List<Logement>.from(_logements);

    // 1. Chip type rapide
    if (_filtreTypeActif != 'Tous') {
      final t = _n(_filtreTypeActif);
      result = result
          .where((l) =>
              _n(l.typeBien).contains(t) || _n(l.typeLocation).contains(t))
          .toList();
    }

    // 2. Texte de recherche (titre, type, ville, quartier, description)
    if (_texteRecherche.isNotEmpty) {
      final q = _n(_texteRecherche);
      result = result
          .where((l) =>
              _n(l.titre).contains(q) ||
              _n(l.typeBien).contains(q) ||
              _n(l.typeLocation).contains(q) ||
              _n(l.ville).contains(q) ||
              _n(l.quartier).contains(q) ||
              _n(l.description).contains(q))
          .toList();
    }

    // 3. Filtres avancés
    final f = _filtresAvances;
    if (f.typeBien != null) {
      final tb = _n(f.typeBien!);
      result = result.where((l) => _n(l.typeBien).contains(tb)).toList();
    }
    if (f.typeLocation != null) {
      final tl = _n(f.typeLocation!);
      result = result.where((l) => _n(l.typeLocation).contains(tl)).toList();
    }
    if (f.prixMin != null) {
      result = result.where((l) => l.prix >= f.prixMin!).toList();
    }
    if (f.prixMax != null && f.prixMax! < 1000000) {
      result = result.where((l) => l.prix <= f.prixMax!).toList();
    }
    if (f.seulementVerifies) {
      result = result.where((l) => l.estVerifie).toList();
    }

    return result;
  }

  int get _nombreFiltresActifs {
    int n = 0;
    if (_filtresAvances.typeBien != null) n++;
    if (_filtresAvances.typeLocation != null) n++;
    if (_filtresAvances.prixMin != null || _filtresAvances.prixMax != null) n++;
    if (_filtresAvances.seulementVerifies) n++;
    return n;
  }

  void _onSearchChanged(String query) {
    setState(() {
      _texteRecherche = query;
      if (query.isEmpty) {
        _suggestions = [];
        return;
      }
      final q = _n(query);
      final Set<String> suggs = {};
      for (final l in _logements) {
        if (_n(l.titre).contains(q))    suggs.add(l.titre);
        if (_n(l.quartier).contains(q)) suggs.add(l.quartier);
        if (_n(l.ville).contains(q))    suggs.add(l.ville);
        if (_n(l.typeBien).contains(q)) suggs.add(l.typeBien);
      }
      _suggestions = suggs.take(6).toList();
    });
  }

  void _appliquerSuggestion(String sugg) {
    _searchController.text = sugg;
    setState(() {
      _texteRecherche = sugg;
      _suggestions    = [];
    });
  }

  // ── Actions ──────────────────────────────────────────────────
  void _lancerRecherche(String query) {
    AnalyticsService.instance.logRechercheLogement(
      ville: query.isNotEmpty ? query : null,
      type: _filtreTypeActif == 'Tous' ? null : _filtreTypeActif,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListeLogementsScreen(
          recherche: query,
          filtreType: _filtreTypeActif == 'Tous' ? null : _filtreTypeActif,
        ),
      ),
    );
  }

  void _ouvrirDetail(Logement logement) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailLogementScreen(logement: logement)),
    );
  }

  Future<void> _afficherFiltresAvances() async {
    final result = await showModalBottomSheet<FiltreRecherche>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FiltresAvancesSheet(filtreActuel: _filtresAvances),
    );
    if (result != null && mounted) {
      setState(() => _filtresAvances = result);
    }
  }

  // ── Build principal ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ① Bandeau offline – toujours visible au-dessus du scroll
            _BandeauOffline(
              visible: !_estConnecte,
              dateDernierCache: _dateDernierCache,
            ),
            // ② Corps principal
            Expanded(
              child: _isLoading
                  ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
                  : _erreurSansCache
                  ? _buildErreurSansCache()
                  : _buildCorps(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bouton messagerie avec badge ─────────────────────────────
  Widget _buildMessagesBtn() {
    return StreamBuilder<QuerySnapshot>(
      stream: _currentUid != null
          ? MessagerieService.getConversations(_currentUid!)
          : const Stream.empty(),
      builder: (context, snap) {
        int unread = 0;
        if (snap.hasData && _currentUid != null) {
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            if ((d['unread_$_currentUid'] as int? ?? 0) > 0) unread++;
          }
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              tooltip: _l.t('messages_title'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessagerieScreen()),
              ),
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Corps scrollable ─────────────────────────────────────────
  Widget _buildCorps() {
    final filtres    = _logementsFiltres;
    final sponsories = _logements.where((l) => l.estSponsorie).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _chargerDonnees,
      child: CustomScrollView(
        slivers: [

          // ─── APP BAR gradient + barre de recherche ────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.primary,
            actions: [_buildMessagesBtn(), const _LanguageSelector()],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryDark, AppColors.primary],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Logo
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 40, height: 40, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.home,
                                        color: Colors.white, size: 24),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ImmoConnect',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Cameroun',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _l.t('accueil_tagline'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                height: 56,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: sw.AppSearchBar(
                  controller: _searchController,
                  onSearch: (q) {
                    setState(() { _texteRecherche = q; _suggestions = []; });
                  },
                  onChanged: _onSearchChanged,
                  onFilterTap: _afficherFiltresAvances,
                  filtresActifsCount: _nombreFiltresActifs,
                ),
              ),
            ),
          ),

          // ─── FILTRES RAPIDES ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _typesBiens.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final item  = _typesBiens[i];
                    final value = item['value'] as String;
                    final label = _l.t(item['key'] as String);
                    return sw.AppFilterChip(
                      label: label,
                      selected: _filtreTypeActif == value,
                      icon: item['icon'] as IconData,
                      onTap: () => setState(() {
                        _filtreTypeActif = value;
                        if (value != 'Tous') _lancerRecherche('');
                      }),
                    );
                  },
                ),
              ),
            ),
          ),

          // ─── SUGGESTIONS AUTOCOMPLÉTION ──────────────────────
          if (_suggestions.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.map((s) => InkWell(
                    onTap: () => _appliquerSuggestion(s),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(children: [
                        const Icon(Icons.search,
                            size: 16, color: AppColors.textHint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s,
                              style: TextStyle(
                                  color: context.appTextPrimary,
                                  fontSize: 14)),
                        ),
                        const Icon(Icons.north_west,
                            size: 14, color: AppColors.textHint),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            ),

          // ─── ANNONCES SPONSORISÉES (carrousel) ───────────────
          if (sponsories.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: sw.SectionTitle(
                title: _l.t('accueil_featured'),
                onVoirTout: () => _lancerRecherche(''),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 220,
                child: PageView.builder(
                  controller: PageController(viewportFraction: 0.9),
                  itemCount: sponsories.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _SponsoredCard(
                      logement: sponsories[i],
                      onTap: () => _ouvrirDetail(sponsories[i]),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ─── PUBLICITÉS PRESTATAIRES ─────────────────────────
          const SliverToBoxAdapter(child: sw.PublicitePrestataireBanner()),

          // ─── BANNIÈRE PUBLICITAIRE ────────────────────────────
          const SliverToBoxAdapter(child: sw.PubliciteBanner()),

          // ─── EN-TÊTE SECTION RECOMMANDÉS ─────────────────────
          SliverToBoxAdapter(
            child: sw.SectionTitle(
              title: _l.t('accueil_recommended'),
              onVoirTout: () => _lancerRecherche(''),
            ),
          ),

          // ─── LISTE LOGEMENTS (pub intercalée 1 / 5) ──────────
          if (filtres.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (_texteRecherche.isNotEmpty ||
                                _filtresAvances.aDesFiltres)
                            ? Icons.search_off
                            : Icons.home_work_outlined,
                        size: 52,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (_texteRecherche.isNotEmpty ||
                                _filtresAvances.aDesFiltres)
                            ? _l.t('search_no_result')
                            : _l.t('accueil_no_listings'),
                        style: AppTextStyles.h3.copyWith(
                            color: AppColors.textHint),
                        textAlign: TextAlign.center,
                      ),
                      if (_texteRecherche.isNotEmpty ||
                          _filtresAvances.aDesFiltres) ...[
                        const SizedBox(height: 8),
                        Text(
                          _l.t('search_no_result_hint'),
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _texteRecherche = '';
                            _filtresAvances = const FiltreRecherche();
                            _searchController.clear();
                            _suggestions = [];
                          }),
                          icon: const Icon(Icons.clear_all),
                          label: Text(_l.t('filter_reset')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  // Insérer une bannière pub tous les 5 logements
                  if (i > 0 && i % 5 == 0) {
                    return const sw.PubliciteBanner();
                  }
                  final idx = i - (i ~/ 5);
                  if (idx >= filtres.length) return null;
                  return sw.LogementCard(
                    logement: filtres[idx],
                    onTap: () => _ouvrirDetail(filtres[idx]),
                  );
                },
                childCount: filtres.length + (filtres.length ~/ 5),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // ── État erreur sans cache ───────────────────────────────────
  Widget _buildErreurSansCache() {
    return sw.EmptyState(
      icon: Icons.wifi_off_rounded,
      title: _l.t('accueil_load_error'),
      subtitle: _l.t('accueil_load_error_sub'),
      action: ElevatedButton.icon(
        icon: const Icon(Icons.refresh),
        label: Text(_l.t('common_retry')),
        onPressed: _chargerDonnees,
      ),
    );
  }
}

// ============================================================
// WIDGET : Carte annonce sponsorisée (style premium)
// ============================================================

class _SponsoredCard extends StatelessWidget {
  final Logement logement;
  final VoidCallback onTap;

  const _SponsoredCard({required this.logement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo
              logement.photos.isNotEmpty
                  ? Image.network(
                logement.photos.first,
                fit: BoxFit.cover,
                errorBuilder: (context, __, ___) => Container(
                  color: context.appPrimaryLight,
                  child: const Icon(Icons.home,
                      size: 60, color: AppColors.primary),
                ),
              )
                  : Builder(builder: (ctx) => Container(
                color: ctx.appPrimaryLight,
                child: const Icon(Icons.home,
                    size: 60, color: AppColors.primary),
              )),

              // Gradient overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.4, 1.0],
                  ),
                ),
              ),

              // Texte en bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context).t('common_sponsored'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        logement.titre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${logement.quartier}, ${logement.ville}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            logement.prixLabel,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Badge vérifié
              if (logement.estVerifie)
                const Positioned(
                  top: 12,
                  right: 12,
                  child: Icon(Icons.verified, color: Colors.white, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET : Sélecteur de langue FR / EN + toggle thème
// ============================================================

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  static const _langues = [
    {'code': 'fr', 'flag': '🇫🇷', 'label': 'FR'},
    {'code': 'en', 'flag': '🇬🇧', 'label': 'EN'},
  ];

  void _changerLangue(BuildContext context) {
    final ctrl        = AppController.instance;
    final currentCode = ctrl.locale.languageCode;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text(
            'Choisir la langue',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ..._langues.map((l) => ListTile(
            leading: Text(l['flag']!, style: const TextStyle(fontSize: 24)),
            title: Text(l['label'] == 'FR' ? 'Français' : 'English'),
            trailing: currentCode == l['code']
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              ctrl.setLocale(Locale(l['code']!));
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl     = AppController.instance;
    final langCode = ctrl.locale.languageCode;
    final flag     = _langues.firstWhere(
          (l) => l['code'] == langCode,
      orElse: () => _langues.first,
    )['flag']!;
    final isDark = ctrl.isDark;

    return Row(
      children: [
        // Toggle thème clair / sombre
        GestureDetector(
          onTap: () => ctrl.toggleTheme(),
          child: Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white38),
            ),
            child: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        // Sélecteur de langue
        GestureDetector(
          onTap: () => _changerLangue(context),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white38),
            ),
            child: Row(
              children: [
                Text(flag, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  langCode.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BOTTOM SHEET : Filtres avancés
// ============================================================

class _FiltresAvancesSheet extends StatefulWidget {
  final FiltreRecherche filtreActuel;
  const _FiltresAvancesSheet({required this.filtreActuel});

  @override
  State<_FiltresAvancesSheet> createState() => _FiltresAvancesSheetState();
}

class _FiltresAvancesSheetState extends State<_FiltresAvancesSheet> {
  late RangeValues _prixRange;
  late String?     _typeBien;
  late String?     _typeTransaction;
  late bool        _seulementVerifies;

  @override
  void initState() {
    super.initState();
    final f = widget.filtreActuel;
    _prixRange         = RangeValues(f.prixMin ?? 0, f.prixMax ?? 1000000);
    _typeBien          = f.typeBien;
    _typeTransaction   = f.typeLocation;
    _seulementVerifies = f.seulementVerifies;
  }

  void _reinitialiser() => setState(() {
    _prixRange         = const RangeValues(0, 1000000);
    _typeBien          = null;
    _typeTransaction   = null;
    _seulementVerifies = false;
  });

  void _appliquer() {
    final filtre = FiltreRecherche(
      typeBien:         _typeBien,
      typeLocation:     _typeTransaction,
      prixMin:          _prixRange.start > 0 ? _prixRange.start : null,
      prixMax:          _prixRange.end < 1000000 ? _prixRange.end : null,
      seulementVerifies: _seulementVerifies,
    );
    Navigator.pop(context, filtre);
  }

  int get _nFiltres {
    int n = 0;
    if (_typeBien != null) n++;
    if (_typeTransaction != null) n++;
    if (_prixRange.start > 0 || _prixRange.end < 1000000) n++;
    if (_seulementVerifies) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          // Poignée
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.t('accueil_filter'), style: AppTextStyles.h2),
              TextButton(
                onPressed: _reinitialiser,
                child: Text(l.t('filter_reset'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            ],
          ),
          if (_nFiltres > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${l.t('filter_active_count')} : $_nFiltres',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(),
          const SizedBox(height: 12),

          // Type de transaction
          Text(l.t('filter_transaction_type'), style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Row(children: [
            _RadioChip(
              label: l.t('filter_rental'),
              value: 'location',
              groupValue: _typeTransaction,
              onChanged: (v) => setState(() =>
                  _typeTransaction = _typeTransaction == v ? null : v),
            ),
            const SizedBox(width: 8),
            _RadioChip(
              label: l.t('filter_sale'),
              value: 'vente',
              groupValue: _typeTransaction,
              onChanged: (v) => setState(() =>
                  _typeTransaction = _typeTransaction == v ? null : v),
            ),
          ]),
          const SizedBox(height: 16),

          // Type de bien
          Text(l.t('filter_property_type'), style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              for (final t in ['Studio', 'Appartement', 'Villa',
                               'Terrain', 'Bureau', 'Commerce'])
                _RadioChip(
                  label: t,
                  value: t,
                  groupValue: _typeBien,
                  onChanged: (v) => setState(() =>
                      _typeBien = _typeBien == v ? null : v),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Fourchette de prix
          Text(l.t('filter_budget'), style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(
            '${_formatPrix(_prixRange.start.toInt())} XAF'
            '  —  '
            '${_prixRange.end >= 1000000 ? l.t('filter_price_max_label') : "${_formatPrix(_prixRange.end.toInt())} XAF"}',
            style: AppTextStyles.bodyMedium,
          ),
          RangeSlider(
            values: _prixRange,
            min: 0,
            max: 1000000,
            divisions: 100,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _prixRange = v),
          ),
          const SizedBox(height: 12),

          // Prestataires vérifiés uniquement
          SwitchListTile(
            title: Text(l.t('filter_verified_only')),
            subtitle: Text(l.t('filter_verified_only_sub'),
                style: const TextStyle(fontSize: 12)),
            value: _seulementVerifies,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
            onChanged: (v) => setState(() => _seulementVerifies = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 24),

          // Bouton appliquer
          ElevatedButton(
            onPressed: _appliquer,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50)),
            child: Text(l.t('filter_apply')),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatPrix(int valeur) => valeur
      .toString()
      .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
}

// ============================================================
// WIDGET : Chip radio réutilisable (filtres avancés)
// ============================================================

class _RadioChip extends StatelessWidget {
  final String  label;
  final String  value;
  final String? groupValue;
  final ValueChanged<String> onChanged;

  const _RadioChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = groupValue == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.appTextSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET : Bandeau hors-connexion animé
// ============================================================

class _BandeauOffline extends StatelessWidget {
  final bool      visible;
  final DateTime? dateDernierCache;

  const _BandeauOffline({required this.visible, this.dateDernierCache});

  String _formaterDate(DateTime date) {
    final formatter = DateFormat("d MMMM yyyy 'à' HH'h'mm", 'fr_FR');
    return formatter.format(date);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: visible
          ? Container(
        width: double.infinity,
        color: const Color(0xFFF97316), // orange-500
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Text('📡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Builder(builder: (context) {
                final l = AppLocalizations.of(context);
                return Text(
                  dateDernierCache != null
                      ? '${l.t('accueil_offline_cache')} ${_formaterDate(dateDernierCache!)}'
                      : l.t('accueil_offline_no_cache'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }),
            ),
          ],
        ),
      )
          : const SizedBox.shrink(),
    );
  }
}