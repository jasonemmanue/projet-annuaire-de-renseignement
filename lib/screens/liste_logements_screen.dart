import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart' as sw;
import 'detail_logement_screen.dart';

// ============================================================
// FICHIER : lib/screens/liste_logements_screen.dart
// Ecran 3 - Liste des logements (§4.1.3)
// Grille ou liste, tri, pagination infinie, lazy loading
// ============================================================

class ListeLogementsScreen extends StatefulWidget {
  final String? recherche;
  final String? filtreType;

  const ListeLogementsScreen({super.key, this.recherche, this.filtreType});

  @override
  State<ListeLogementsScreen> createState() => _ListeLogementsScreenState();
}

class _ListeLogementsScreenState extends State<ListeLogementsScreen> {
  bool _isGridView = false;
  String _triActif = 'recents';
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final List<Logement> _logements = List.from(_mockLogements);
  int _page = 1;
  bool _hasMore = true;

  final List<Map<String, String>> _options = [
    {'value': 'recents', 'label': 'Plus recents'},
    {'value': 'prix_asc', 'label': 'Prix croissant'},
    {'value': 'prix_desc', 'label': 'Prix decroissant'},
    {'value': 'populaires', 'label': 'Populaires'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _chargerPlus();
    }
  }

  Future<void> _chargerPlus() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _page++;
      _isLoading = false;
      if (_page > 3) _hasMore = false;
    });
  }

  // ✅ CORRIGE : _logementsFiltrés → _logementsFiltres (suppression du é)
  List<Logement> get _logementsFiltres {
    var liste = List<Logement>.from(_logements);
    if (widget.filtreType != null && widget.filtreType != 'Tous') {
      liste = liste.where((l) =>
      l.typeBien.toLowerCase().contains(widget.filtreType!.toLowerCase()) ||
          l.typeLocation.toLowerCase().contains(widget.filtreType!.toLowerCase())
      ).toList();
    }
    if (widget.recherche != null && widget.recherche!.isNotEmpty) {
      final q = widget.recherche!.toLowerCase();
      liste = liste.where((l) =>
      l.titre.toLowerCase().contains(q) ||
          l.ville.toLowerCase().contains(q) ||
          l.quartier.toLowerCase().contains(q)
      ).toList();
    }
    switch (_triActif) {
      case 'prix_asc':  liste.sort((a, b) => a.prix.compareTo(b.prix)); break;
      case 'prix_desc': liste.sort((a, b) => b.prix.compareTo(a.prix)); break;
      case 'populaires': liste.sort((a, b) => b.nbVues.compareTo(a.nbVues)); break;
      default: liste.sort((a, b) => b.datePublication.compareTo(a.datePublication));
    }
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ CORRIGE : utilise _logementsFiltres
    final logements = _logementsFiltres;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recherche != null && widget.recherche!.isNotEmpty
              ? '"${widget.recherche}"'
              : widget.filtreType ?? 'Tous les logements',
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
          // BARRE DE TRI + RESULTATS
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${logements.length} logement${logements.length > 1 ? 's' : ''}',
                  style: AppTextStyles.bodyMedium,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _afficherTri(context),
                  child: Row(
                    children: [
                      const Icon(Icons.sort, size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        _options.firstWhere((o) => o['value'] == _triActif)['label']!,
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

          // LISTE / GRILLE
          Expanded(
            child: logements.isEmpty
                ? sw.EmptyState(
              icon: Icons.home_work_outlined,
              title: 'Aucun logement trouve',
              subtitle: 'Essayez de modifier vos criteres de recherche',
              action: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Retour'),
              ),
            )
                : _isGridView
                ? _buildGridView(logements)
                : _buildListView(logements),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<Logement> logements) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: logements.length + (_isLoading ? 1 : 0) + (logements.length ~/ 5),
      itemBuilder: (_, i) {
        if (i > 0 && i % 6 == 5) return const sw.PubliciteBanner();
        final idx = i - (i ~/ 6);
        if (idx >= logements.length) {
          return _isLoading
              ? const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
              : _hasMore
              ? const SizedBox()
              : const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'Plus de logements a charger',
                style: TextStyle(color: AppColors.textHint),
              ),
            ),
          );
        }
        return sw.LogementCard(
          logement: logements[idx],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailLogementScreen(logement: logements[idx])),
          ),
        );
      },
    );
  }

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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailLogementScreen(logement: logements[i])),
        ),
        isGrid: true,
      ),
    );
  }

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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Trier par', style: AppTextStyles.h3),
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
}

// Donnees mock
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