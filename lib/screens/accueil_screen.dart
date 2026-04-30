import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart' as sw;
import 'liste_logements_screen.dart';
import 'detail_logement_screen.dart';

// ============================================================
// FICHIER : lib/screens/accueil_screen.dart
// Écran 1 - Page d'accueil / Menu principal (§4.1.1)
// Inspiré Booking.com : barre de recherche proéminente,
// catégories, annonces sponsorisées, recommandés près de vous
// ============================================================

class AccueilScreen extends StatefulWidget {
  const AccueilScreen({super.key});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

class _AccueilScreenState extends State<AccueilScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filtreTypeActif = 'Tous';
  bool _isLoading = false;

  // Types de biens pour les filtres rapides (§4.1.1)
  final List<Map<String, dynamic>> _typesBiens = [
    {'label': 'Tous', 'icon': Icons.apps},
    {'label': 'Studio', 'icon': Icons.single_bed},
    {'label': 'F2/F3', 'icon': Icons.bed},
    {'label': 'Villa', 'icon': Icons.villa},
    {'label': 'Terrain', 'icon': Icons.landscape},
    {'label': 'Location', 'icon': Icons.home_work_outlined},
    {'label': 'Vente', 'icon': Icons.sell_outlined},
  ];

  // Données fictives pour le dev (à remplacer par API)
  final List<Logement> _logementsSponsorises = _mockLogements.where((l) => l.estSponsorie).toList();
  final List<Logement> _logementsProches = _mockLogements;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _lancerRecherche(String query) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ─── APP BAR avec recherche intégrée ───────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryDark, AppColors.primary],
                  ),
                ),
                child: SafeArea(
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
                                // Logo SGK HOME
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 40,
                                      height: 40,
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'SGK HOME',
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
                            // Sélecteur de langue (§3.1 UC-C10)
                            _LanguageSelector(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Trouvez votre logement idéal',
                          style: TextStyle(
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
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: sw.SearchBar(
                  controller: _searchController,
                  onSearch: _lancerRecherche,
                  onFilterTap: () => _afficherFiltresAvances(context),
                ),
              ),
            ),
          ),

          // ─── FILTRES RAPIDES ────────────────────────────────────
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
                    final item = _typesBiens[i];
                    return sw.FilterChip(
                      label: item['label'],
                      selected: _filtreTypeActif == item['label'],
                      icon: item['icon'],
                      onTap: () => setState(() {
                        _filtreTypeActif = item['label'];
                        if (item['label'] != 'Tous') {
                          _lancerRecherche('');
                        }
                      }),
                    );
                  },
                ),
              ),
            ),
          ),

          // ─── ANNONCES SPONSORISÉES (carrousel, max 3) ──────────
          if (_logementsSponsorises.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sw.SectionTitle(
                    title: '⭐ Annonces à la une',
                    onVoirTout: () => _lancerRecherche(''),
                  ),
                  SizedBox(
                    height: 220,
                    child: PageView.builder(
                      controller: PageController(viewportFraction: 0.9),
                      itemCount: _logementsSponsorises.take(3).length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _SponsoredCard(
                          logement: _logementsSponsorises[i],
                          onTap: () => _ouvrirDetail(_logementsSponsorises[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ─── PUBLICITÉ (1 pub toutes les 5 annonces - §2.1.2) ──
          const SliverToBoxAdapter(child: sw.PubliciteBanner()),

          // ─── RECOMMANDÉS PRÈS DE VOUS ──────────────────────────
          SliverToBoxAdapter(
            child: sw.SectionTitle(
              title: '📍 Recommandés près de vous',
              onVoirTout: () => _lancerRecherche(''),
            ),
          ),

          // Liste des logements proches
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (_, i) {
                // Insérer une pub toutes les 5 annonces (§2.1.2)
                if (i > 0 && i % 5 == 0) {
                  return const sw.PubliciteBanner();
                }
                final idx = i - (i ~/ 5);
                if (idx >= _logementsProches.length) return null;
                return sw.LogementCard(
                  logement: _logementsProches[idx],
                  onTap: () => _ouvrirDetail(_logementsProches[idx]),
                );
              },
              childCount: _logementsProches.length + (_logementsProches.length ~/ 5),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _ouvrirDetail(Logement logement) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailLogementScreen(logement: logement)),
    );
  }

  void _afficherFiltresAvances(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FiltresAvancesSheet(),
    );
  }
}

// ----------------------------------------------------------
// CARTE ANNONCE SPONSORISÉE (style premium)
// ----------------------------------------------------------
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              logement.photos.isNotEmpty
                  ? Image.network(logement.photos.first, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.primaryLight, child: const Icon(Icons.home, size: 60, color: AppColors.primary)))
                  : Container(color: AppColors.primaryLight, child: const Icon(Icons.home, size: 60, color: AppColors.primary)),
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
              // Contenu texte en bas
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
                        child: const Text('Sponsorisé', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black)),
                      ),
                      const SizedBox(height: 4),
                      Text(logement.titre,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${logement.quartier}, ${logement.ville}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(logement.prixLabel,
                              style: const TextStyle(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (logement.estVerifie)
                const Positioned(top: 12, right: 12, child: Icon(Icons.verified, color: Colors.white, size: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// SÉLECTEUR DE LANGUE (FR / EN - §3.1 UC-C10)
// ----------------------------------------------------------
class _LanguageSelector extends StatefulWidget {
  @override
  State<_LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<_LanguageSelector> {
  String _lang = 'FR';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _lang = _lang == 'FR' ? 'EN' : 'FR'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          children: [
            Text(_lang == 'FR' ? '🇫🇷' : '🇬🇧', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(_lang, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// BOTTOM SHEET FILTRES AVANCÉS (§4.1.1 + §3.1 UC-C02)
// ----------------------------------------------------------
class _FiltresAvancesSheet extends StatefulWidget {
  const _FiltresAvancesSheet();

  @override
  State<_FiltresAvancesSheet> createState() => _FiltresAvancesSheetState();
}

class _FiltresAvancesSheetState extends State<_FiltresAvancesSheet> {
  RangeValues _prixRange = const RangeValues(0, 500000);
  String? _typeBien;
  String? _typeLocation;
  bool _seulementVerifies = false;

  @override
  Widget build(BuildContext context) {
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
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filtres', style: AppTextStyles.h2),
              TextButton(
                onPressed: () {
                  setState(() {
                    _prixRange = const RangeValues(0, 500000);
                    _typeBien = null;
                    _typeLocation = null;
                    _seulementVerifies = false;
                  });
                },
                child: const Text('Réinitialiser', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),

          // Type de transaction
          const Text('Type de transaction', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Row(children: [
            _RadioChip(label: 'Location', value: 'location', groupValue: _typeLocation,
                onChanged: (v) => setState(() => _typeLocation = v)),
            const SizedBox(width: 8),
            _RadioChip(label: 'Vente', value: 'vente', groupValue: _typeLocation,
                onChanged: (v) => setState(() => _typeLocation = v)),
          ]),
          const SizedBox(height: 16),

          // Type de bien
          const Text('Type de bien', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in ['Studio', 'F2', 'F3', 'Villa', 'Terrain', 'Appartement'])
              _RadioChip(label: t, value: t, groupValue: _typeBien,
                  onChanged: (v) => setState(() => _typeBien = v)),
          ]),
          const SizedBox(height: 16),

          // Fourchette de prix
          const Text('Budget (XAF)', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(
            '${_prixRange.start.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} '
                'XAF — ${_prixRange.end.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} XAF',
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
            title: const Text('Prestataires vérifiés uniquement'),
            subtitle: const Text('Afficher les annonces avec badge vérifié', style: TextStyle(fontSize: 12)),
            value: _seulementVerifies,
            activeColor: AppColors.primary,
            onChanged: (v) => setState(() => _seulementVerifies = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 24),

          // Bouton appliquer
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Appliquer les filtres via Provider/Bloc
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: const Text('Appliquer les filtres'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _RadioChip extends StatelessWidget {
  final String label;
  final String value;
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
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// DONNÉES MOCK (à remplacer par API REST)
// ----------------------------------------------------------
final List<Logement> _mockLogements = [
  Logement(
    id: '1', titre: 'Studio moderne à Bastos',
    description: 'Beau studio entièrement meublé avec accès internet, idéal pour jeunes professionnels.',
    prix: 150000, typeLocation: 'location', typeBien: 'Studio',
    ville: 'Yaoundé', quartier: 'Bastos',
    latitude: 3.8667, longitude: 11.5167,
    photos: ['https://picsum.photos/seed/logement1/400/300'],
    surface: 30, nbPieces: 1,
    equipements: ['Meublé', 'Wifi', 'Climatiseur', 'Eau chaude'],
    estVerifie: true, estSponsorie: true,
    prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 6XX XXX XXX',
    datePublication: DateTime.now().subtract(const Duration(days: 2)),
    nbVues: 234, disponible: true,
  ),
  Logement(
    id: '2', titre: 'Villa F4 à Bonanjo',
    description: 'Grande villa avec jardin, parking, 4 chambres. Quartier résidentiel calme.',
    prix: 450000, typeLocation: 'location', typeBien: 'Villa',
    ville: 'Douala', quartier: 'Bonanjo',
    latitude: 4.0511, longitude: 9.7679,
    photos: ['https://picsum.photos/seed/logement2/400/300'],
    surface: 200, nbPieces: 4,
    equipements: ['Jardin', 'Parking', 'Gardien', 'Groupe électrogène'],
    estVerifie: true, estSponsorie: true,
    prestatireId: 'p2', prestatireNom: 'Marie Bello', prestatirePhone: '+237 6XX XXX XXX',
    datePublication: DateTime.now().subtract(const Duration(days: 1)),
    nbVues: 512, disponible: true,
  ),
  Logement(
    id: '3', titre: 'Appartement F2 à Akwa',
    description: 'Appartement F2 au 3e étage, vue dégagée, bien entretenu.',
    prix: 85000, typeLocation: 'location', typeBien: 'F2',
    ville: 'Douala', quartier: 'Akwa',
    latitude: 4.0435, longitude: 9.6935,
    photos: ['https://picsum.photos/seed/logement3/400/300'],
    surface: 55, nbPieces: 2,
    equipements: ['Climatiseur', 'Eau chaude', 'Sécurisé'],
    estVerifie: false, estSponsorie: false,
    prestatireId: 'p3', prestatireNom: 'Paul Ngono', prestatirePhone: '+237 6XX XXX XXX',
    datePublication: DateTime.now().subtract(const Duration(days: 5)),
    nbVues: 87, disponible: true,
  ),
];