import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'detail_logement_screen.dart';

// ============================================================
// FICHIER : lib/screens/carte_screen.dart
// Écran 2 - Navigateur / Carte interactive (§4.1.2)
// Google Maps avec marqueurs, clustering, géolocalisation,
// filtre de distance, fiche résumé cliquable
// ============================================================

class CarteScreen extends StatefulWidget {
  const CarteScreen({super.key});

  @override
  State<CarteScreen> createState() => _CarteScreenState();
}

class _CarteScreenState extends State<CarteScreen> {
  Logement? _logementSelectionne;
  double _distanceFiltreKm = 5.0;
  bool _isLocating = false;

  // Distances disponibles pour le filtre (§4.1.2)
  final List<double> _distances = [0.5, 1.0, 5.0, 10.0];

  // Mock data - à remplacer par appel API
  final List<Logement> _logements = _mockLogements;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _afficherFiltreDistance(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ─── CARTE PRINCIPALE ────────────────────────────────
          // TODO: Remplacer par GoogleMap widget
          // Nécessite : google_maps_flutter dans pubspec.yaml
          // + Clé API Google Maps Platform (§7.2 - $0-200/mois)
          _PlaceholderCarte(
            logements: _logements,
            onMarkerTap: (logement) => setState(() => _logementSelectionne = logement),
          ),

          // ─── FILTRE DISTANCE (§4.1.2) ─────────────────────────
          Positioned(
            top: 12,
            left: 12,
            child: _FiltreDistanceWidget(
              distanceActuelle: _distanceFiltreKm,
              distances: _distances,
              onChanged: (d) => setState(() => _distanceFiltreKm = d),
            ),
          ),

          // ─── BOUTON GÉOLOCALISATION (§4.1.2) ─────────────────
          Positioned(
            right: 12,
            bottom: _logementSelectionne != null ? 200 : 30,
            child: Column(
              children: [
                _MapButton(
                  icon: _isLocating ? Icons.gps_fixed : Icons.gps_not_fixed,
                  onTap: _localiserUtilisateur,
                  color: _isLocating ? AppColors.primary : Colors.white,
                  iconColor: _isLocating ? Colors.white : AppColors.textPrimary,
                ),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.add, onTap: () {/* Zoom + */}),
                const SizedBox(height: 4),
                _MapButton(icon: Icons.remove, onTap: () {/* Zoom - */}),
              ],
            ),
          ),

          // ─── COMPTEUR LOGEMENTS ───────────────────────────────
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Text(
                '${_logements.length} logements',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // ─── FICHE RÉSUMÉ CLIQUABLE (§4.1.2) ─────────────────
          if (_logementSelectionne != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _FicheResume(
                logement: _logementSelectionne!,
                onClose: () => setState(() => _logementSelectionne = null),
                onVoirDetail: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailLogementScreen(logement: _logementSelectionne!),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _localiserUtilisateur() async {
    setState(() => _isLocating = true);
    // TODO: Intégrer geolocator package
    // final position = await Geolocator.getCurrentPosition();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isLocating = false);
  }

  void _afficherFiltreDistance(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Distance maximale', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            ...['500 m', '1 km', '5 km', '10 km'].asMap().entries.map((e) {
              final vals = [0.5, 1.0, 5.0, 10.0];
              return ListTile(
                title: Text(e.value),
                trailing: _distanceFiltreKm == vals[e.key]
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _distanceFiltreKm = vals[e.key]);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// PLACEHOLDER CARTE (avant intégration Google Maps)
// ----------------------------------------------------------
class _PlaceholderCarte extends StatelessWidget {
  final List<Logement> logements;
  final ValueChanged<Logement> onMarkerTap;

  const _PlaceholderCarte({required this.logements, required this.onMarkerTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFE8F0E9),
      child: Stack(
        children: [
          // Grille simulant une carte
          CustomPaint(painter: _GridPainter()),
          // Centre - indicateur
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map, size: 48, color: AppColors.textHint),
                const SizedBox(height: 8),
                const Text('Carte Google Maps', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const Text('Intégrez google_maps_flutter', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Marqueurs simulés
          ...logements.asMap().entries.map((e) {
            final positions = [
              const Offset(0.35, 0.4), const Offset(0.6, 0.35),
              const Offset(0.25, 0.6), const Offset(0.7, 0.55),
            ];
            final pos = positions[e.key % positions.length];
            return Positioned(
              left: MediaQuery.of(context).size.width * pos.dx,
              top: (MediaQuery.of(context).size.height - kToolbarHeight - kBottomNavigationBarHeight) * pos.dy,
              child: GestureDetector(
                onTap: () => onMarkerTap(e.value),
                child: _Marqueur(logement: e.value),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ----------------------------------------------------------
// MARQUEUR DE LOGEMENT SUR CARTE
// ----------------------------------------------------------
class _Marqueur extends StatelessWidget {
  final Logement logement;
  const _Marqueur({required this.logement});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: logement.estSponsorie ? AppColors.accent : AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Text(
            logement.prixLabel,
            style: TextStyle(
              color: logement.estSponsorie ? Colors.black87 : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        CustomPaint(
          painter: _MarkerTriangle(logement.estSponsorie ? AppColors.accent : AppColors.primary),
          size: const Size(12, 6),
        ),
      ],
    );
  }
}

class _MarkerTriangle extends CustomPainter {
  final Color color;
  _MarkerTriangle(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ----------------------------------------------------------
// FILTRE DISTANCE (chips horizontaux)
// ----------------------------------------------------------
class _FiltreDistanceWidget extends StatelessWidget {
  final double distanceActuelle;
  final List<double> distances;
  final ValueChanged<double> onChanged;

  const _FiltreDistanceWidget({
    required this.distanceActuelle,
    required this.distances,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labels = ['500m', '1km', '5km', '10km'];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: distances.asMap().entries.map((e) {
          final selected = distanceActuelle == e.value;
          return GestureDetector(
            onTap: () => onChanged(e.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                labels[e.key],
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ----------------------------------------------------------
// BOUTON FLOTTANT CARTE
// ----------------------------------------------------------
class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.iconColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)],
      ),
      child: Icon(icon, color: iconColor, size: 20),
    ),
  );
}

// ----------------------------------------------------------
// FICHE RÉSUMÉ CLIQUABLE (preview depuis carte §4.1.2)
// ----------------------------------------------------------
class _FicheResume extends StatelessWidget {
  final Logement logement;
  final VoidCallback onClose;
  final VoidCallback onVoirDetail;

  const _FicheResume({
    required this.logement,
    required this.onClose,
    required this.onVoirDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 0),
            child: Row(
              children: [
                // Photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: logement.photos.isNotEmpty
                      ? Image.network(logement.photos.first, width: 80, height: 80, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: AppColors.primaryLight, child: const Icon(Icons.home, color: AppColors.primary)))
                      : Container(width: 80, height: 80, color: AppColors.primaryLight, child: const Icon(Icons.home, color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(logement.titre, style: AppTextStyles.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${logement.quartier}, ${logement.ville}', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text(logement.prixLabel, style: AppTextStyles.price.copyWith(fontSize: 16)),
                        const SizedBox(width: 8),
                        if (logement.estVerifie)
                          const Icon(Icons.verified, color: AppColors.primary, size: 16),
                      ]),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onClose),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: ElevatedButton(
              onPressed: onVoirDetail,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
              child: const Text('Voir le détail'),
            ),
          ),
        ],
      ),
    );
  }
}

// Mock data
final List<Logement> _mockLogements = [
  Logement(id: '1', titre: 'Studio à Bastos', description: 'Studio meublé.', prix: 150000,
      typeLocation: 'location', typeBien: 'Studio', ville: 'Yaoundé', quartier: 'Bastos',
      latitude: 3.8667, longitude: 11.5167, photos: ['https://picsum.photos/seed/l1/400/300'],
      surface: 30, nbPieces: 1, equipements: ['Meublé'], estVerifie: true, estSponsorie: true,
      prestatireId: 'p1', prestatireNom: 'Jean Dupont', prestatirePhone: '+237 655 123 456',
      datePublication: DateTime.now(), nbVues: 234, disponible: true),
  Logement(id: '2', titre: 'Villa Bonanjo', description: 'Grande villa.', prix: 450000,
      typeLocation: 'location', typeBien: 'Villa', ville: 'Douala', quartier: 'Bonanjo',
      latitude: 4.0511, longitude: 9.7679, photos: ['https://picsum.photos/seed/l2/400/300'],
      surface: 200, nbPieces: 4, equipements: ['Jardin'], estVerifie: true, estSponsorie: false,
      prestatireId: 'p2', prestatireNom: 'Marie Bello', prestatirePhone: '+237 677 987 654',
      datePublication: DateTime.now(), nbVues: 512, disponible: true),
  Logement(id: '3', titre: 'F2 Akwa', description: 'Appartement F2.', prix: 85000,
      typeLocation: 'location', typeBien: 'F2', ville: 'Douala', quartier: 'Akwa',
      latitude: 4.0435, longitude: 9.6935, photos: ['https://picsum.photos/seed/l3/400/300'],
      surface: 55, nbPieces: 2, equipements: ['Climatiseur'], estVerifie: false, estSponsorie: false,
      prestatireId: 'p3', prestatireNom: 'Paul Ngono', prestatirePhone: '+237 690 456 789',
      datePublication: DateTime.now(), nbVues: 87, disponible: true),
];