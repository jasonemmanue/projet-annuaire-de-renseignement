import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart' as sw;
import 'detail_logement_screen.dart';
import '../services/analytics_service.dart';
import '../services/cache_service.dart';
import '../services/logement_service.dart';

// ============================================================
// FICHIER : lib/screens/liste_logements_screen.dart
// Écran 3 – Liste des logements (§4.1.3)
// Grille ou liste, tri, pagination infinie, lazy loading,
// support hors-connexion + bandeau offline + cache SharedPrefs
// ============================================================

class ListeLogementsScreen extends StatefulWidget {
  final String? recherche;
  final String? filtreType;

  const ListeLogementsScreen({super.key, this.recherche, this.filtreType});

  @override
  State<ListeLogementsScreen> createState() => _ListeLogementsScreenState();
}

class _ListeLogementsScreenState extends State<ListeLogementsScreen> {
  // ── Affichage ────────────────────────────────────────────────
  bool _isGridView = false;
  String _triActif = 'recents';

  // ── Données ──────────────────────────────────────────────────
  List<Logement> _logements = [];
  bool _isLoading = true;
  bool _erreurSansCache = false;

  // ── Pagination infinie ───────────────────────────────────────
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // ── Connectivité ─────────────────────────────────────────────
  bool _estConnecte = true;
  DateTime? _dateDernierCache;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  late AppLocalizations _l;

  // ── Options de tri (computed from locale) ────────────────────
  List<Map<String, String>> get _options => [
    {'value': 'recents',    'label': _l.t('sort_recent')},
    {'value': 'prix_asc',   'label': _l.t('sort_price_asc')},
    {'value': 'prix_desc',  'label': _l.t('sort_price_desc')},
    {'value': 'populaires', 'label': _l.t('sort_popular')},
  ];

  // ── Cycle de vie ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initConnectivite();
    _chargerDonnees();
    // [ANALYTICS] Vue liste logements
    AnalyticsService.instance.logScreenView('liste_logements');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _scrollController.dispose();
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

      // Connexion retrouvée → rafraîchir depuis Firestore
      if (connecte && etaitDeconnecte) {
        await _chargerDepuisFirestore(mettreAJourUI: true);
      }
    });
  }

  Future<bool> _verifierConnexion() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  // ── Chargement ───────────────────────────────────────────────
  Future<void> _chargerDonnees() async {
    setState(() {
      _isLoading = true;
      _erreurSansCache = false;
      _page = 1;
      _hasMore = true;
    });

    _estConnecte = await _verifierConnexion();

    if (_estConnecte) {
      await _chargerDepuisFirestore(mettreAJourUI: false);
    } else {
      await _chargerDepuisCache();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _chargerDepuisFirestore({required bool mettreAJourUI}) async {
    try {
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
      debugPrint('[ListeLogementsScreen] Firestore error: $e');
      await _chargerDepuisCache();
    }
  }

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

  // ── Pagination infinie (scroll) ──────────────────────────────
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _chargerPlus();
    }
  }

  Future<void> _chargerPlus() async {
    if (_isLoadingMore || !_hasMore || !_estConnecte) return;
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _page++;
      _isLoadingMore = false;
      if (_page > 3) _hasMore = false;
    });
  }

  // ── Filtrage + tri ───────────────────────────────────────────
  List<Logement> get _logementsFiltres {
    var liste = List<Logement>.from(_logements);

    if (widget.filtreType != null && widget.filtreType != 'Tous') {
      liste = liste
          .where((l) =>
      l.typeBien
          .toLowerCase()
          .contains(widget.filtreType!.toLowerCase()) ||
          l.typeLocation
              .toLowerCase()
              .contains(widget.filtreType!.toLowerCase()))
          .toList();
    }

    if (widget.recherche != null && widget.recherche!.isNotEmpty) {
      final q = widget.recherche!.toLowerCase();
      liste = liste
          .where((l) =>
      l.titre.toLowerCase().contains(q) ||
          l.ville.toLowerCase().contains(q) ||
          l.quartier.toLowerCase().contains(q))
          .toList();
    }

    switch (_triActif) {
      case 'prix_asc':
        liste.sort((a, b) => a.prix.compareTo(b.prix));
        break;
      case 'prix_desc':
        liste.sort((a, b) => b.prix.compareTo(a.prix));
        break;
      case 'populaires':
        liste.sort((a, b) => b.nbVues.compareTo(a.nbVues));
        break;
      default:
        liste.sort((a, b) => b.datePublication.compareTo(a.datePublication));
    }
    return liste;
  }

  // ── Build principal ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recherche != null && widget.recherche!.isNotEmpty
              ? '"${widget.recherche}"'
              : widget.filtreType ?? _l.t('liste_title'),
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: Column(
        children: [
          // ① Bandeau hors-connexion
          _BandeauOffline(
            visible: !_estConnecte,
            dateDernierCache: _dateDernierCache,
          ),

          // ② Corps
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
    );
  }

  Widget _buildCorps() {
    final logements = _logementsFiltres;

    return Column(
      children: [
        // Barre tri + compteur
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${logements.length} logement${logements.length > 1 ? 's' : ''}',
                style: AppTextStyles.bodyMedium,
              ),
              // Indicateur cache discret
              if (!_estConnecte) ...[
                const SizedBox(width: 8),
                const Icon(Icons.cloud_off, size: 14, color: AppColors.textHint),
                const SizedBox(width: 2),
                const Text(
                  'cache',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => _afficherTri(context),
                child: Row(
                  children: [
                    const Icon(Icons.sort, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      _options.firstWhere(
                              (o) => o['value'] == _triActif)['label']!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Liste / Grille
        Expanded(
          child: logements.isEmpty
              ? sw.EmptyState(
            icon: Icons.home_work_outlined,
            title: _l.t('liste_no_results'),
            subtitle: _l.t('liste_no_results_sub'),
            action: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l.t('common_back')),
            ),
          )
              : RefreshIndicator(
            color: AppColors.primary,
            // Refresh manuel désactivé hors-ligne
            onRefresh: _estConnecte ? _chargerDonnees : () async {},
            child: _isGridView
                ? _buildGridView(logements)
                : _buildListView(logements),
          ),
        ),
      ],
    );
  }

  // ── Liste ────────────────────────────────────────────────────
  Widget _buildListView(List<Logement> logements) {
    return ListView.builder(
      controller: _scrollController,
      // Intercale une pub toutes les 6 cartes
      itemCount:
      logements.length + (_isLoadingMore ? 1 : 0) + (logements.length ~/ 5),
      itemBuilder: (_, i) {
        if (i > 0 && i % 6 == 5) return const sw.PubliciteBanner();

        final idx = i - (i ~/ 6);

        if (idx >= logements.length) {
          if (_isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          if (!_hasMore) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  _l.t('liste_end'),
                  style: const TextStyle(color: AppColors.textHint),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        return sw.LogementCard(
          logement: logements[idx],
          onTap: () => _ouvrirDetail(logements[idx]),
        );
      },
    );
  }

  // ── Grille ───────────────────────────────────────────────────
  Widget _buildGridView(List<Logement> logements) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: logements.length,
      itemBuilder: (_, i) => sw.LogementCard(
        logement: logements[i],
        onTap: () => _ouvrirDetail(logements[i]),
        isGrid: true,
      ),
    );
  }

  // ── Erreur sans cache ────────────────────────────────────────
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

  // ── Modal de tri ─────────────────────────────────────────────
  void _afficherTri(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context).t('sort_by'), style: AppTextStyles.h3),
            ),
            const Divider(),
            ..._options.map((o) => ListTile(
              title: Text(o['label']!),
              trailing: _triActif == o['value']
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _triActif = o['value']!);
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _ouvrirDetail(Logement logement) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailLogementScreen(logement: logement),
      ),
    );
  }
}

// ============================================================
// WIDGET : Bandeau hors-connexion
// Note : si vous en avez besoin dans d'autres écrans, déplacez
//        ce widget dans lib/widgets/shared_widgets.dart
// ============================================================

class _BandeauOffline extends StatelessWidget {
  final bool visible;
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
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

// ============================================================
// DONNÉES MOCK (conservées pour les tests hors Firestore)
// ============================================================

// ignore: unused_element
final List<Logement> _mockLogements = [
  Logement(
    id: '1', titre: 'Studio moderne a Bastos',
    description: 'Beau studio entierement meuble avec acces internet.',
    prix: 150000, typeLocation: 'location', typeBien: 'Studio',
    ville: 'Yaounde', quartier: 'Bastos', latitude: 3.8667, longitude: 11.5167,
    photos: ['https://picsum.photos/seed/logement1/400/300'],
    surface: 30, nbPieces: 1,
    equipements: ['Meuble', 'Wifi', 'Climatiseur'],
    estVerifie: true, estSponsorie: true,
    prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 655 123 456',
    datePublication: DateTime.now().subtract(const Duration(days: 2)), nbVues: 234, disponible: true,
  ),
  Logement(
    id: '2', titre: 'Villa F4 a Bonanjo', description: 'Grande villa avec jardin.',
    prix: 450000, typeLocation: 'location', typeBien: 'Villa',
    ville: 'Douala', quartier: 'Bonanjo', latitude: 4.0511, longitude: 9.7679,
    photos: ['https://picsum.photos/seed/logement2/400/300'],
    surface: 200, nbPieces: 4,
    equipements: ['Jardin', 'Parking', 'Gardien'],
    estVerifie: true, estSponsorie: false,
    prestatireId: 'p2', prestatireNom: 'Marie Bello', prestatirePhone: '+237 677 987 654',
    datePublication: DateTime.now().subtract(const Duration(days: 1)), nbVues: 512, disponible: true,
  ),
  Logement(
    id: '3', titre: 'Appartement F2 a Akwa', description: 'Appartement F2 au 3e etage.',
    prix: 85000, typeLocation: 'location', typeBien: 'F2',
    ville: 'Douala', quartier: 'Akwa', latitude: 4.0435, longitude: 9.6935,
    photos: ['https://picsum.photos/seed/logement3/400/300'],
    surface: 55, nbPieces: 2,
    equipements: ['Climatiseur', 'Eau chaude'],
    estVerifie: false, estSponsorie: false,
    prestatireId: 'p3', prestatireNom: 'Paul Ngono', prestatirePhone: '+237 690 456 789',
    datePublication: DateTime.now().subtract(const Duration(days: 5)), nbVues: 87, disponible: true,
  ),
  Logement(
    id: '4', titre: 'Terrain a Mendong', description: 'Terrain de 500m2 viabilise.',
    prix: 8000000, typeLocation: 'vente', typeBien: 'Terrain',
    ville: 'Yaounde', quartier: 'Mendong', latitude: 3.8200, longitude: 11.4900,
    photos: ['https://picsum.photos/seed/logement4/400/300'],
    surface: 500, nbPieces: 0,
    equipements: ['Titre foncier', 'Electricite', 'Eau'],
    estVerifie: true, estSponsorie: false,
    prestatireId: 'p4', prestatireNom: 'Cabinet Immobilier Pro', prestatirePhone: '+237 222 345 678',
    datePublication: DateTime.now().subtract(const Duration(days: 10)), nbVues: 320, disponible: true,
  ),
];