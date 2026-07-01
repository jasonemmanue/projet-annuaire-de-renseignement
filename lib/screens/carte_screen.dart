import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/logement_service.dart';
import '../services/geolocation_service.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'detail_logement_screen.dart';

// ============================================================
// FICHIER : lib/screens/carte_screen.dart
// #6 Carte réelle — filtrage rayon, cercle, >10 km, anti-chevauchement
// ============================================================

// Sentinelle « > 10 km » = pas de filtre de distance, pas de cercle.
const double _kNoFilterSentinel = 999.0;

class CarteScreen extends StatefulWidget {
  const CarteScreen({super.key});

  @override
  State<CarteScreen> createState() => _CarteScreenState();
}

class _CarteScreenState extends State<CarteScreen> {
  static const Map<String, Color> _typeCouleurs = {
    'Chambre':           Color(0xFF0071C2),
    'Studio':            Color(0xFF7C3AED),
    'Appartement':       Color(0xFFE67E22),
    'Villa':             Color(0xFF28A745),
    'Terrain':           Color(0xFF8B4513),
    'Bureau':            Color(0xFF00897B),
    'Commerce':          Color(0xFF00897B),
    'Pharmacie':         Color(0xFFE91E63),
    'Restaurant / Snack':Color(0xFFFF5722),
    'Entreprise':        Color(0xFF1565C0),
    'École':             Color(0xFF9C27B0),
  };

  static Color _couleurPourType(String typeBien) =>
      _typeCouleurs[typeBien] ?? AppColors.primary;

  Logement? _logementSelectionne;
  double _distanceFiltreKm = 5.0;
  bool _isLocating = false;

  final List<double> _distances = [0.5, 1.0, 5.0, 10.0, _kNoFilterSentinel];

  GoogleMapController? _mapController;

  LatLng? _positionUtilisateur;
  LatLng? _centreFiltre;

  // Cache des icônes custom par logement id
  final Map<String, BitmapDescriptor> _iconCache = {};
  Set<Marker> _markers = {};
  List<Logement> _lastLogements = [];

  static const LatLng _yaoundeCenter = LatLng(3.8480, 11.5021);

  bool get _isFiltering =>
      _centreFiltre != null && _distanceFiltreKm < _kNoFilterSentinel;

  bool _dansLeRayon(Logement l) {
    if (!_isFiltering) return true;
    final distanceM = Geolocator.distanceBetween(
      _centreFiltre!.latitude,
      _centreFiltre!.longitude,
      l.latitude,
      l.longitude,
    );
    return distanceM <= _distanceFiltreKm * 1000;
  }

  /// Génère un BitmapDescriptor avec le nom de l'annonce dans une bulle colorée.
  Future<BitmapDescriptor> _creerIconePerso(String titre, Color couleur) async {
    final label = titre.length > 18 ? '${titre.substring(0, 16)}…' : titre;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Mesurer le texte
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textW = textPainter.width;
    const paddingH = 20.0;
    const paddingV = 12.0;
    final bubbleW = textW + paddingH * 2;
    final bubbleH = textPainter.height + paddingV * 2;
    const arrowH = 16.0;
    final totalW = bubbleW;
    final totalH = bubbleH + arrowH;

    // Bulle arrondie
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, bubbleW, bubbleH),
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()..color = couleur);

    // Ombre fine
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rrect, Paint()..color = couleur);

    // Flèche vers le bas
    final arrowPath = Path()
      ..moveTo(bubbleW / 2 - 10, bubbleH)
      ..lineTo(bubbleW / 2, bubbleH + arrowH)
      ..lineTo(bubbleW / 2 + 10, bubbleH)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = couleur);

    // Texte centré
    textPainter.paint(canvas, Offset(paddingH, paddingV));

    final picture = recorder.endRecording();
    final img = await picture.toImage(totalW.ceil(), totalH.ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Construit les marqueurs de manière asynchrone avec icônes personnalisées.
  Future<void> _buildMarkersAsync(List<Logement> logements) async {
    final visibles = logements
        .where((l) => l.latitude != 0 || l.longitude != 0)
        .where(_dansLeRayon)
        .toList();

    final Set<Marker> newMarkers = {};

    for (final l in visibles) {
      // Générer l'icône si pas encore en cache
      if (!_iconCache.containsKey(l.id)) {
        final couleur = _couleurPourType(l.typeBien);
        _iconCache[l.id] = await _creerIconePerso(l.titre, couleur);
      }

      newMarkers.add(Marker(
        markerId: MarkerId(l.id),
        position: LatLng(l.latitude, l.longitude),
        icon: _iconCache[l.id]!,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(title: l.titre, snippet: l.prixLabel),
        onTap: () => setState(() => _logementSelectionne = l),
      ));
    }

    // Marqueur centre du rayon
    if (_centreFiltre != null && _centreFiltre != _positionUtilisateur) {
      newMarkers.add(Marker(
        markerId: const MarkerId('_centre_rayon'),
        position: _centreFiltre!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Centre du rayon'),
      ));
    }

    if (mounted) setState(() => _markers = newMarkers);
  }

  /// Appelé quand la liste change ou quand le filtre change.
  void _rafraichirMarkers() {
    _buildMarkersAsync(_lastLogements);
  }

  Set<Circle> _buildCircles() {
    if (!_isFiltering) return const {};
    return {
      Circle(
        circleId: const CircleId('rayon_filtre'),
        center: _centreFiltre!,
        radius: _distanceFiltreKm * 1000,
        strokeWidth: 2,
        strokeColor: AppColors.primary,
        fillColor: AppColors.primary.withValues(alpha: 0.08),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottomOffset = _logementSelectionne != null ? 200.0 : 30.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('carte_title')),
        actions: [
          if (_centreFiltre != null)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Effacer le rayon',
              onPressed: () {
                setState(() => _centreFiltre = null);
                _rafraichirMarkers();
              },
            ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _afficherFiltreDistance(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: LogementService.getLogements(),
        builder: (ctx, snap) {
          final logements = snap.hasData
              ? snap.data!.docs
                  .map((d) =>
                      Logement.fromMap(d.id, d.data() as Map<String, dynamic>))
                  .where((l) => l.estVisiblePourVisiteur)
                  .toList()
              : <Logement>[];

          // Reconstruire les marqueurs si les données ont changé
          if (logements.length != _lastLogements.length ||
              (logements.isNotEmpty && _lastLogements.isNotEmpty &&
               logements.first.id != _lastLogements.first.id)) {
            _lastLogements = logements;
            _buildMarkersAsync(logements);
          } else if (_lastLogements.isEmpty && logements.isNotEmpty) {
            _lastLogements = logements;
            _buildMarkersAsync(logements);
          }

          final circles = _buildCircles();

          return Stack(
            children: [
              // ─── CARTE GOOGLE MAPS ────────────────────────────
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: _yaoundeCenter, zoom: 12),
                onMapCreated: (ctrl) => _mapController = ctrl,
                markers: _markers,
                circles: circles,
                myLocationEnabled: _positionUtilisateur != null,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                onTap: (latlng) {
                  setState(() => _centreFiltre = latlng);
                  _rafraichirMarkers();
                },
              ),

              // ─── FILTRE DISTANCE (haut-gauche) ───────────────
              Positioned(
                top: 12,
                left: 12,
                child: _FiltreDistanceWidget(
                  distanceActuelle: _distanceFiltreKm,
                  distances: _distances,
                  onChanged: (d) {
                    setState(() => _distanceFiltreKm = d);
                    _rafraichirMarkers();
                  },
                ),
              ),

              // ─── HINT « appuyer sur la carte » si aucun centre ───
              if (_centreFiltre == null)
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        l.t('carte_tap_to_set_center'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),

              // ─── BOUTONS DROITE (GPS + zoom) ─────────────────
              Positioned(
                right: 12,
                bottom: bottomOffset,
                child: Column(
                  children: [
                    _MapButton(
                      icon: _isLocating
                          ? Icons.gps_fixed
                          : Icons.gps_not_fixed,
                      onTap: _localiserUtilisateur,
                      color:
                          _centreFiltre == _positionUtilisateur && _centreFiltre != null
                              ? AppColors.primary
                              : Colors.white,
                      iconColor:
                          _centreFiltre == _positionUtilisateur && _centreFiltre != null
                              ? Colors.white
                              : context.appTextPrimary,
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                        icon: Icons.add,
                        onTap: () =>
                            _mapController?.animateCamera(CameraUpdate.zoomIn())),
                    const SizedBox(height: 4),
                    _MapButton(
                        icon: Icons.remove,
                        onTap: () =>
                            _mapController
                                ?.animateCamera(CameraUpdate.zoomOut())),
                  ],
                ),
              ),

              // ─── BADGE HOREM+ (bas-centre, discret) ─────
              Positioned(
                bottom: _logementSelectionne != null ? 195 : 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Horem+',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),

              // ─── FICHE RÉSUMÉ CLIQUABLE ───────────────────────
              if (_logementSelectionne != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _FicheResume(
                    logement: _logementSelectionne!,
                    onClose: () =>
                        setState(() => _logementSelectionne = null),
                    onVoirDetail: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailLogementScreen(
                            logement: _logementSelectionne!),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _localiserUtilisateur() async {
    setState(() => _isLocating = true);
    try {
      final pos = await GeolocationService.getCurrentPosition();
      if (pos != null && mounted) {
        final latlng = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _positionUtilisateur = latlng;
          _centreFiltre = latlng;
        });
        _rafraichirMarkers();
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latlng, 14));
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _afficherFiltreDistance(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = [
      '500 m',
      '1 km',
      '5 km',
      '10 km',
      l.t('carte_more_than_10km')
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('carte_max_distance'), style: AppTextStyles.h3),
            const SizedBox(height: 16),
            ...List.generate(_distances.length, (i) {
              final val = _distances[i];
              return ListTile(
                title: Text(labels[i]),
                trailing: _distanceFiltreKm == val
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _distanceFiltreKm = val);
                  _rafraichirMarkers();
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

  String _label(BuildContext context, double d) {
    if (d >= _kNoFilterSentinel) {
      return AppLocalizations.of(context).t('carte_more_than_10km');
    }
    if (d < 1.0) return '${(d * 1000).toInt()}m';
    return '${d.toInt()}km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: distances.map((d) {
          final selected = distanceActuelle == d;
          return GestureDetector(
            onTap: () => onChanged(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _label(context, d),
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : context.appTextSecondary,
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
  final Color? iconColor;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.iconColor,
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
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6)
            ],
          ),
          child:
              Icon(icon, color: iconColor ?? context.appTextPrimary, size: 20),
        ),
      );
}

// ----------------------------------------------------------
// FICHE RÉSUMÉ CLIQUABLE (preview depuis carte)
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
    final primaryLight = context.appPrimaryLight;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: logement.photos.isNotEmpty
                      ? Image.network(
                          logement.photos.first,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 80,
                              height: 80,
                              color: primaryLight,
                              child: const Icon(Icons.home,
                                  color: AppColors.primary)),
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: primaryLight,
                          child: const Icon(Icons.home,
                              color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(logement.titre,
                          style: AppTextStyles.h3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${logement.quartier}, ${logement.ville}',
                          style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 4),
                      Row(children: [
                        Flexible(
                          child: Text(logement.prixLabel,
                              style:
                                  AppTextStyles.price.copyWith(fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        if (logement.estVerifie)
                          const Icon(Icons.verified,
                              color: AppColors.primary, size: 16),
                        if (logement.estSponsorie)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.star,
                                color: AppColors.accent, size: 16),
                          ),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: ElevatedButton(
              onPressed: onVoirDetail,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
              child: Text(
                  AppLocalizations.of(context).t('carte_see_detail')),
            ),
          ),
        ],
      ),
    );
  }
}
