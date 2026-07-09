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
import '../services/rating_service.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart' as sw;
import '../app_controller.dart';
import 'liste_logements_screen.dart';
import 'detail_logement_screen.dart';
import 'messagerie_screen.dart';
import 'urgence_screen.dart';

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
  List<_Suggestion> _suggestions = [];
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

  // ── Carrousel « À la une » ───────────────────────────────────
  PageController _alaUneCtrl = PageController(viewportFraction: 0.9);
  Timer? _alaUneTimer;
  int _prevAlaUneCount = 0;
  int _alaUneGeneration = 0;

  List<Logement> get _aLaUne {
    final sponsories = _logements.where((l) => l.estSponsorie).toList();
    if (sponsories.isNotEmpty) return sponsories;
    return _logements.where((l) => l.estVisiblePourVisiteur).take(5).toList();
  }

  void _demarrerTimerAlaUne() {
    _alaUneTimer?.cancel();
    final count = _aLaUne.length;

    if (count != _prevAlaUneCount) {
      _prevAlaUneCount = count;
      _alaUneGeneration++;
      _alaUneCtrl.dispose();
      _alaUneCtrl = PageController(viewportFraction: 0.9);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lancerTimerAlaUne(count);
      });
      return;
    }

    _lancerTimerAlaUne(count);
  }

  void _lancerTimerAlaUne(int count) {
    _alaUneTimer?.cancel();
    if (count <= 1) return;
    _alaUneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_alaUneCtrl.hasClients) return;
      final current = _alaUneCtrl.page?.round() ?? 0;
      final next = (current + 1) % count;
      _alaUneCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

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
    _initRating();
  }

  Future<void> _initRating() async {
    await RatingService.instance.incrementOpenCount();
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await RatingService.instance.maybeAskForReview(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _alaUneTimer?.cancel();
    _alaUneCtrl.dispose();
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
    if (mounted) {
      setState(() => _isLoading = false);
      _demarrerTimerAlaUne();
    }
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
        _demarrerTimerAlaUne();
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

  /// Extrait un montant numérique d'une requête de recherche.
  /// Ex: "chambre 10000" → 10000, "50 000" → 50000, "25k" → 25000
  static ({double? montant, String texte}) _extraireBudget(String query) {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return (montant: null, texte: cleaned);

    // "25k" / "25K" → 25000
    final kMatch = RegExp(r'(\d+)\s*[kK]').firstMatch(cleaned);
    if (kMatch != null) {
      final val = double.tryParse(kMatch.group(1)!);
      if (val != null) {
        final reste = cleaned.replaceFirst(kMatch.group(0)!, '').trim();
        return (montant: val * 1000, texte: reste);
      }
    }

    // "10 000" ou "10000" (nombres avec ou sans espaces)
    final numMatch = RegExp(r'(\d[\d\s]{2,})').firstMatch(cleaned);
    if (numMatch != null) {
      final raw = numMatch.group(1)!.replaceAll(' ', '');
      final val = double.tryParse(raw);
      if (val != null && val >= 1000) {
        final reste = cleaned.replaceFirst(numMatch.group(0)!, '').trim();
        return (montant: val, texte: reste);
      }
    }

    // Nombre simple ≥ 1000 (ex: "10000")
    final simpleMatch = RegExp(r'(\d{4,})').firstMatch(cleaned);
    if (simpleMatch != null) {
      final val = double.tryParse(simpleMatch.group(1)!);
      if (val != null) {
        final reste = cleaned.replaceFirst(simpleMatch.group(0)!, '').trim();
        return (montant: val, texte: reste);
      }
    }

    return (montant: null, texte: cleaned);
  }

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

    // 2. Texte de recherche + budget
    if (_texteRecherche.isNotEmpty) {
      final parsed = _extraireBudget(_texteRecherche);
      final budget = parsed.montant;
      final texte = parsed.texte;

      // Filtrer par texte (titre, type, ville, quartier, description)
      if (texte.isNotEmpty) {
        final q = _n(texte);
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

      // Filtrer par budget (tolérance ±10% pour des résultats pertinents)
      if (budget != null) {
        final min = budget * 0.9;
        final max = budget * 1.1;
        result = result.where((l) => l.prix >= min && l.prix <= max).toList();
      }
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

    // Tri par priorité : sponsorisé → publication active → expiré
    result.sort((a, b) => a.prioriteAffichage.compareTo(b.prioriteAffichage));
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

      final parsed = _extraireBudget(query);
      final budget = parsed.montant;
      final texte = parsed.texte;
      final q = _n(query);

      final Map<String, _Suggestion> suggs = {};
      for (final l in _logements) {
        if (_n(l.titre).contains(q)) {
          suggs.putIfAbsent(l.titre, () => _Suggestion(
            label: l.titre,
            prix: l.prixFormate,
            searchText: l.titre,
          ));
        }
        if (_n(l.quartier).contains(q)) {
          suggs.putIfAbsent('q_${l.quartier}', () => _Suggestion(
            label: l.quartier,
            prix: null,
            searchText: l.quartier,
          ));
        }
        if (_n(l.ville).contains(q)) {
          suggs.putIfAbsent('v_${l.ville}', () => _Suggestion(
            label: l.ville,
            prix: null,
            searchText: l.ville,
          ));
        }
        if (_n(l.typeBien).contains(q)) {
          suggs.putIfAbsent('t_${l.typeBien}', () => _Suggestion(
            label: l.typeBien,
            prix: null,
            searchText: l.typeBien,
          ));
        }

        if (budget != null) {
          final min = budget * 0.9;
          final max = budget * 1.1;
          if (l.prix >= min && l.prix <= max) {
            if (texte.isEmpty || _n(l.titre).contains(_n(texte)) ||
                _n(l.typeBien).contains(_n(texte))) {
              suggs.putIfAbsent('b_${l.id}', () => _Suggestion(
                label: l.titre,
                prix: l.prixFormate,
                searchText: l.titre,
              ));
            }
          }
        }
      }
      _suggestions = suggs.values.take(8).toList();
    });
  }

  void _appliquerSuggestion(_Suggestion sugg) {
    _searchController.text = sugg.searchText;
    setState(() {
      _texteRecherche = sugg.searchText;
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
      body: sw.SkylineBackground(
        child: SafeArea(
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
      ),
      floatingActionButton: const _UrgenceFab(),
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
    final filtres = _logementsFiltres;
    final aLaUne  = _aLaUne;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _chargerDonnees,
      child: CustomScrollView(
        slivers: [

          // ─── APP BAR gradient + skyline + barre de recherche ────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Colors.transparent,
            actions: [_buildMessagesBtn(), const _LanguageSelector()],
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Logo
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 44, height: 44, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.home,
                                        color: Colors.white, size: 26),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Horem+',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Cameroun',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12,
                                      letterSpacing: 0.3),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _l.t('accueil_tagline'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                          child: Text(s.label,
                              style: TextStyle(
                                  color: context.appTextPrimary,
                                  fontSize: 14)),
                        ),
                        if (s.prix != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(s.prix!,
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                        const SizedBox(width: 8),
                        const Icon(Icons.north_west,
                            size: 14, color: AppColors.textHint),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            ),

          // ─── BANNIÈRE PUBLICITAIRE ────────────────────────────
          const SliverToBoxAdapter(child: sw.PubliciteBanner()),

          // ─── « À LA UNE » — toujours visible ─────────────────
          if (aLaUne.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête discret sans fond coloré
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.accent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _l.t('accueil_featured'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              letterSpacing: 0.3,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _lancerRecherche(''),
                          child: Text(
                            _l.t('accueil_see_all'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Carrousel auto-défilant
                  SizedBox(
                    height: 220,
                    child: PageView.builder(
                      key: ValueKey('alaune_$_alaUneGeneration'),
                      controller: _alaUneCtrl,
                      itemCount: aLaUne.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _SponsoredCard(
                          logement: aLaUne[i],
                          onTap: () => _ouvrirDetail(aLaUne[i]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

          // ─── PUBLICITÉS PRESTATAIRES (sous À la une) ─────────
          const SliverToBoxAdapter(child: sw.PublicitePrestataireBanner()),

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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 11, color: Colors.black87),
                            const SizedBox(width: 3),
                            Text(
                              AppLocalizations.of(context).t('common_sponsored'),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ],
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

              // Badge étoile À la une
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Colors.black87, size: 16),
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

class _Suggestion {
  final String label;
  final String? prix;
  final String searchText;
  const _Suggestion({required this.label, this.prix, required this.searchText});
}

// ── FAB Urgence animé (pulse rouge) ──────────────────────────

class _UrgenceFab extends StatefulWidget {
  const _UrgenceFab();

  @override
  State<_UrgenceFab> createState() => _UrgenceFabState();
}

class _UrgenceFabState extends State<_UrgenceFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ScaleTransition(
      scale: _scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'urgenceFab',
            backgroundColor: Colors.red.shade600,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UrgenceScreen()),
            ),
            child: const Icon(Icons.notifications_active,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            loc.t('urgence_fab_label'),
            style: TextStyle(
              color: Colors.red.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}