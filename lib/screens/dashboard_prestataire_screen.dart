// ============================================================
// FICHIER : lib/screens/dashboard_prestataire_screen.dart
// IMMOCONNECT – Dashboard prestataire v5
// ✅ Onglets : Mes annonces | Messages | Statistiques | Profil
// ✅ Badge non-lus temps réel sur l'onglet Messages
// ✅ Profil prestataire dédié : infos, service client, déco
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/geolocation_service.dart';
import '../services/logement_service.dart';
import '../services/storage_service.dart';
import '../app_controller.dart';
import 'messagerie_screen.dart';

// ============================================================
// FORMULAIRE AJOUT / MODIFICATION ANNONCE
// ============================================================
class FormulaireAnnonce extends StatefulWidget {
  final Logement? logement;
  const FormulaireAnnonce({super.key, this.logement});

  @override
  State<FormulaireAnnonce> createState() => _FormulaireAnnonceState();
}

class _FormulaireAnnonceState extends State<FormulaireAnnonce> {
  final _formKey = GlobalKey<FormState>();
  final _titreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();

  String _typeLocation = 'location';
  String _typeBien = 'Studio';
  String _ville = 'Yaoundé';
  final List<String> _equipements = [];
  bool _isSubmitting = false;

  // Géolocalisation
  LatLng? _positionSelectionnee;
  String _adresseAffichee = 'Appuyez sur "Localiser" pour détecter votre position';
  bool _isLocating = false;
  GoogleMapController? _mapController;

  // Photos
  final List<XFile> _photosSelectionnees = [];
  final List<String> _photosExistantes = [];
  bool _isUploadingPhotos = false;

  final List<String> _typesBiens = ['Studio', 'Appartement', 'Villa', 'Terrain', 'Bureau', 'Commerce'];
  final List<String> _villes = ['Yaoundé', 'Douala', 'Bafoussam', 'Garoua', 'Maroua'];
  final List<String> _equipementsDispos = [
    'Meublé', 'Wifi', 'Climatiseur', 'Eau chaude',
    'Gardien', 'Parking', 'Groupe électrogène', 'Titre foncier'
  ];

  static const LatLng _yaoundeCenter = LatLng(3.8480, 11.5021);

  @override
  void initState() {
    super.initState();
    if (widget.logement != null) {
      final l = widget.logement!;
      _titreCtrl.text = l.titre;
      _descCtrl.text = l.description;
      _prixCtrl.text = l.prix.toString();
      _surfaceCtrl.text = l.surface.toString();
      _quartierCtrl.text = l.quartier;
      _typeLocation = l.typeLocation;
      _typeBien = l.typeBien;
      _ville = l.ville;
      _equipements.addAll(l.equipements);
      _photosExistantes.addAll(l.photos);
      if (l.latitude != 0 && l.longitude != 0) {
        _positionSelectionnee = LatLng(l.latitude, l.longitude);
        _adresseAffichee = '${l.quartier}, ${l.ville}';
      }
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose(); _descCtrl.dispose(); _prixCtrl.dispose();
    _surfaceCtrl.dispose(); _quartierCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _choisirPhotos() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 80, limit: 6);
    if (images.isNotEmpty) setState(() => _photosSelectionnees.addAll(images));
  }

  Future<void> _prendrePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (image != null) setState(() => _photosSelectionnees.add(image));
  }

  Future<void> _localiserMaintenant() async {
    setState(() => _isLocating = true);
    try {
      final position = await GeolocationService.getCurrentPosition();
      if (position == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'obtenir la position.'), backgroundColor: AppColors.error));
        return;
      }
      final latlng = LatLng(position.latitude, position.longitude);
      final adresse = await GeolocationService.getAddressFromCoordinates(position.latitude, position.longitude);
      setState(() { _positionSelectionnee = latlng; _adresseAffichee = adresse; });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latlng, 16));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onMapTap(LatLng position) async {
    setState(() { _positionSelectionnee = position; _adresseAffichee = 'Chargement…'; });
    final adresse = await GeolocationService.getAddressFromCoordinates(position.latitude, position.longitude);
    if (mounted) setState(() => _adresseAffichee = adresse);
  }

  Future<void> _publier() async {
    if (!_formKey.currentState!.validate()) return;
    if (_positionSelectionnee == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Veuillez localiser votre bien sur la carte'),
        backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Utilisateur non connecté');

      List<String> photoUrls = List.from(_photosExistantes);

      if (_photosSelectionnees.isNotEmpty) {
        setState(() => _isUploadingPhotos = true);
        final tempId = widget.logement?.id ??
            FirebaseFirestore.instance.collection('logements').doc().id;
        final urls = await StorageService.uploadMultiplePhotos(
          uid: uid, logementId: tempId, images: _photosSelectionnees);
        photoUrls.addAll(urls);
        setState(() => _isUploadingPhotos = false);
      }

      final data = {
        'titre': _titreCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'prix': double.tryParse(_prixCtrl.text) ?? 0,
        'surface': int.tryParse(_surfaceCtrl.text) ?? 0,
        'quartier': _quartierCtrl.text.trim(),
        'ville': _ville,
        'typeLocation': _typeLocation,
        'typeBien': _typeBien,
        'equipements': _equipements,
        'latitude': _positionSelectionnee!.latitude,
        'longitude': _positionSelectionnee!.longitude,
        'photos': photoUrls,
        'uid_prestataire': uid,
        'disponible': true,
        'isSponsored': false,
      };

      if (widget.logement == null) {
        await LogementService.addLogement(data);
      } else {
        await LogementService.updateLogement(widget.logement!.id, data);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.logement == null ? 'Annonce publiée !' : 'Annonce mise à jour !'),
          backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _isUploadingPhotos = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPhotos = _photosExistantes.length + _photosSelectionnees.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.logement == null ? 'Nouvelle annonce' : 'Modifier l\'annonce')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Photos du bien', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              if (totalPhotos > 0)
                SizedBox(
                  height: 100,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    ..._photosExistantes.asMap().entries.map((e) => _PhotoThumbNet(
                      url: e.value,
                      onDelete: () => setState(() => _photosExistantes.removeAt(e.key)))),
                    ..._photosSelectionnees.asMap().entries.map((e) => _PhotoThumbLocal(
                      path: e.value.path,
                      onDelete: () => setState(() => _photosSelectionnees.removeAt(e.key)))),
                    if (_isUploadingPhotos)
                      Container(width: 90, height: 90, margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border)),
                        child: const Center(child: CircularProgressIndicator())),
                  ]),
                ),
              const SizedBox(height: 8),
              if (totalPhotos < 6)
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _choisirPhotos,
                    icon: const Icon(Icons.photo_library), label: const Text('Galerie'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _prendrePhoto,
                    icon: const Icon(Icons.camera_alt), label: const Text('Caméra'))),
                ]),
              Text('$totalPhotos/6 photos', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 20),
              const Text('Titre de l\'annonce *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _titreCtrl,
                decoration: const InputDecoration(hintText: 'Ex: Studio meublé à Bastos'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null),
              const SizedBox(height: 16),
              const Text('Type de transaction *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _ChoixCard(label: 'Location', icon: Icons.home_work,
                  selected: _typeLocation == 'location',
                  onTap: () => setState(() => _typeLocation = 'location'))),
                const SizedBox(width: 12),
                Expanded(child: _ChoixCard(label: 'Vente', icon: Icons.sell,
                  selected: _typeLocation == 'vente',
                  onTap: () => setState(() => _typeLocation = 'vente'))),
              ]),
              const SizedBox(height: 16),
              const Text('Type de bien *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(value: _typeBien,
                items: _typesBiens.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _typeBien = v!)),
              const SizedBox(height: 16),
              const Text('Ville *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(value: _ville,
                items: _villes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _ville = v!)),
              const SizedBox(height: 16),
              const Text('Quartier *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _quartierCtrl,
                decoration: const InputDecoration(hintText: 'Ex: Bastos, Akwa…'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null),
              const SizedBox(height: 16),
              const Text('Prix (XAF) *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _prixCtrl, keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: 'Ex: 150000',
                  suffixText: _typeLocation == 'location' ? 'XAF/mois' : 'XAF'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null),
              const SizedBox(height: 16),
              const Text('Surface (m²)', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _surfaceCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Ex: 45', suffixText: 'm²')),
              const SizedBox(height: 16),
              const Text('Description *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _descCtrl, maxLines: 4,
                decoration: const InputDecoration(hintText: 'Décrivez votre bien…'),
                validator: (v) => v!.isEmpty ? 'Champ requis' : null),
              const SizedBox(height: 16),
              const Text('Équipements', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: _equipementsDispos.map((eq) {
                  final sel = _equipements.contains(eq);
                  return FilterChip(label: Text(eq), selected: sel,
                    selectedColor: AppColors.primaryLight, checkmarkColor: AppColors.primary,
                    onSelected: (v) => setState(() => v ? _equipements.add(eq) : _equipements.remove(eq)));
                }).toList()),
              const SizedBox(height: 20),
              const Text('Localisation du bien *', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isLocating ? null : _localiserMaintenant,
                icon: _isLocating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.my_location),
                label: Text(_isLocating ? 'Détection en cours…' : 'Détecter ma position GPS'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44))),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _positionSelectionnee != null ? AppColors.primaryLight : AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _positionSelectionnee != null ? AppColors.primary : AppColors.border)),
                child: Row(children: [
                  Icon(_positionSelectionnee != null ? Icons.location_on : Icons.location_off,
                    color: _positionSelectionnee != null ? AppColors.primary : AppColors.textHint, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_adresseAffichee,
                      style: TextStyle(color: _positionSelectionnee != null ? AppColors.primary : AppColors.textHint, fontSize: 13)),
                    if (_positionSelectionnee != null)
                      Text('Lat: ${_positionSelectionnee!.latitude.toStringAsFixed(5)} · Lng: ${_positionSelectionnee!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ])),
                ])),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(height: 200, child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _positionSelectionnee ?? _yaoundeCenter,
                    zoom: _positionSelectionnee != null ? 15 : 12),
                  onMapCreated: (ctrl) => _mapController = ctrl,
                  onTap: _onMapTap,
                  markers: _positionSelectionnee != null ? {Marker(
                    markerId: const MarkerId('bien'),
                    position: _positionSelectionnee!,
                    infoWindow: InfoWindow(title: _titreCtrl.text.isNotEmpty ? _titreCtrl.text : 'Mon bien'))} : {},
                  myLocationButtonEnabled: false, zoomControlsEnabled: false))),
              const SizedBox(height: 4),
              const Text('Appuyez sur la carte pour ajuster la position exacte',
                style: TextStyle(color: AppColors.textHint, fontSize: 11)),
              if (_positionSelectionnee == null)
                const Padding(padding: EdgeInsets.only(top: 4),
                  child: Text('Position requise pour publier l\'annonce',
                    style: TextStyle(color: AppColors.error, fontSize: 12))),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _publier,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: _isSubmitting
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text(_isUploadingPhotos ? 'Upload photos…' : 'Publication…'),
                    ])
                    : Text(widget.logement == null ? 'Publier l\'annonce' : 'Enregistrer les modifications')),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoThumbNet extends StatelessWidget {
  final String url; final VoidCallback onDelete;
  const _PhotoThumbNet({required this.url, required this.onDelete});
  @override
  Widget build(BuildContext context) => _buildThumb(child: Image.network(url, fit: BoxFit.cover), onDelete: onDelete);
}

class _PhotoThumbLocal extends StatelessWidget {
  final String path; final VoidCallback onDelete;
  const _PhotoThumbLocal({required this.path, required this.onDelete});
  @override
  Widget build(BuildContext context) => Stack(children: [
    _buildThumb(child: Image.asset(path, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.image)), onDelete: onDelete),
    Positioned(bottom: 4, left: 4, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
      child: const Text('Nouveau', style: TextStyle(color: Colors.white, fontSize: 9))))
  ]);
}

Widget _buildThumb({required Widget child, required VoidCallback onDelete}) {
  return Stack(children: [
    Container(width: 90, height: 90, margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppColors.background),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child)),
    Positioned(top: 2, right: 10, child: GestureDetector(onTap: onDelete,
      child: Container(decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        child: const Icon(Icons.close, color: Colors.white, size: 16))))
  ]);
}

class _ChoixCard extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _ChoixCard({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.5)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: selected ? Colors.white : AppColors.textSecondary, size: 20),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ])));
}

// ============================================================
// DASHBOARD PRESTATAIRE — Écran principal
// ============================================================
class DashboardPrestataireScreen extends StatefulWidget {
  const DashboardPrestataireScreen({super.key});

  @override
  State<DashboardPrestataireScreen> createState() => _DashboardPrestataireScreenState();
}

class _DashboardPrestataireScreenState extends State<DashboardPrestataireScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  // Langues disponibles
  static const _langues = [
    {'code': 'fr', 'label': 'Français', 'flag': '🇫🇷'},
    {'code': 'en', 'label': 'English', 'flag': '🇬🇧'},
  ];

  @override
  void initState() {
    super.initState();
    // 4 onglets : Mes annonces | Messages | Statistiques | Profil
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _changerLangue(BuildContext context) {
    final ctrl = AppController.instance;
    final currentCode = ctrl.locale.languageCode;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Choisir la langue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ..._langues.map((l) => ListTile(
            leading: Text(l['flag']!, style: const TextStyle(fontSize: 24)),
            title: Text(l['label']!),
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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final user = AuthService.instance.currentUser;
    final isDark = AppController.instance.isDark;
    final langCode = AppController.instance.locale.languageCode;
    final flagEmoji = _langues.firstWhere(
        (l) => l['code'] == langCode,
        orElse: () => _langues.first)['flag']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon espace'),
        actions: [
          // ── Thème clair/sombre ──
          IconButton(
            tooltip: isDark ? 'Mode clair' : 'Mode sombre',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => AppController.instance.toggleTheme(),
          ),
          // ── Drapeau / Langue ──
          GestureDetector(
            onTap: () => _changerLangue(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(flagEmoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          // ── Bouton "Nouvelle annonce" ──
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FormulaireAnnonce()),
              ),
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
              label: const Text(
                'nouvelle\nannonce',
                style: TextStyle(color: Colors.white, fontSize: 10, height: 1.2),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.list_alt), text: 'Annonces'),
            // ── Onglet Messages avec badge non-lus temps réel ──
            Tab(
              child: StreamBuilder<QuerySnapshot>(
                stream: uid.isEmpty
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                        .collection('conversations')
                        .where('participants', arrayContains: uid)
                        // Pas d'orderBy → pas d'index composite requis
                        .snapshots(),
                builder: (ctx, snap) {
                  int totalUnread = 0;
                  if (snap.hasData) {
                    for (final doc in snap.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      totalUnread += (data['unread_$uid'] as int? ?? 0);
                    }
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 20),
                          const SizedBox(height: 1),
                          Text(
                            'Msgs',
                            style: const TextStyle(fontSize: 9),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      if (totalUnread > 0)
                        Positioned(
                          right: -6,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              totalUnread > 9 ? '9+' : '$totalUnread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Tab(icon: Icon(Icons.bar_chart), text: 'Stats'),
            const Tab(icon: Icon(Icons.person), text: 'Profil'),
          ],
          // ── Couleurs toujours visibles ──
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.accent, width: 3),
          ),
        ),
      ),
      body: Column(
        children: [
          // ─── EN-TÊTE PROFIL PRESTATAIRE ────────────────────────
          _ProfilPrestataireHeader(user: user),
          // ─── CONTENU ONGLETS ───────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MesAnnoncesTab(uid: uid),
                MessagerieScreen(forceUid: uid),
                _StatistiquesTab(uid: uid),
                ProfilPrestataireScreen(user: user),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── En-tête profil prestataire ──────────────────────────────
class _ProfilPrestataireHeader extends StatelessWidget {
  final UserModel? user;
  const _ProfilPrestataireHeader({this.user});

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            backgroundImage: (user!.photoUrl != null && user!.photoUrl!.isNotEmpty)
                ? NetworkImage(user!.photoUrl!) as ImageProvider
                : null,
            child: (user!.photoUrl == null || user!.photoUrl!.isEmpty)
                ? Text(
                    (user!.prenom.isNotEmpty ? user!.prenom[0] : '?').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${user!.prenom} ${user!.nom}'.trim(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user!.email,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (user!.isVerifie)
                      _BadgeDash(label: '✓ Vérifié', color: Colors.green.shade400)
                    else
                      _BadgeDash(label: 'Non vérifié', color: Colors.orange.shade300),
                    if (user!.isPremium) ...[
                      const SizedBox(width: 6),
                      _BadgeDash(label: '★ Premium', color: Colors.amber.shade400),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeDash extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgeDash({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 1),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

// ── Onglet "Mes annonces" ─────────────────────────────────────
class _MesAnnoncesTab extends StatelessWidget {
  final String uid;
  const _MesAnnoncesTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: LogementService.getMesLogements(uid),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.home_work_outlined, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                const Text('Aucune annonce publiée',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Appuyez sur + pour créer votre première annonce',
                    style: TextStyle(color: AppColors.textHint, fontSize: 13)),
              ],
            ),
          );
        }

        final logements = snap.data!.docs
            .map((d) => Logement.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logements.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) => _AnnonceCard(
            logement: logements[i],
            onEdit: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => FormulaireAnnonce(logement: logements[i]))),
            onDelete: () => _confirmerSuppression(ctx, logements[i].id),
            onToggleDisponible: () => _toggleDisponible(logements[i]),
          ),
        );
      },
    );
  }

  Future<void> _confirmerSuppression(BuildContext ctx, String id) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer l\'annonce ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) await LogementService.deleteLogement(id);
  }

  Future<void> _toggleDisponible(Logement l) async {
    await LogementService.updateLogement(l.id, {'disponible': !l.disponible});
  }
}

// ── Carte annonce dans le dashboard ──────────────────────────
class _AnnonceCard extends StatelessWidget {
  final Logement logement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleDisponible;

  const _AnnonceCard({
    required this.logement,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleDisponible,
  });

  @override
  Widget build(BuildContext context) {
    final l = logement;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: l.photos.isNotEmpty
                    ? Image.network(l.photos.first, height: 140, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _PhotoPlaceholder())
                    : _PhotoPlaceholder(),
              ),
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: l.disponible ? AppColors.success : AppColors.textHint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(l.disponible ? 'Disponible' : 'Indisponible',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
              Positioned(
                top: 8, right: 8,
                child: Row(
                  children: [
                    _ActionBtn(icon: Icons.edit, color: AppColors.primary, onTap: onEdit),
                    const SizedBox(width: 6),
                    _ActionBtn(icon: Icons.delete_outline, color: AppColors.error, onTap: onDelete),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 2),
                  Text('${l.quartier}, ${l.ville}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const Spacer(),
                  Text(l.prixLabel,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatChip(icon: Icons.visibility_outlined, value: '${l.nbVues}', label: 'vues'),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.people_outline, value: l.typeBien, label: ''),
                    const Spacer(),
                    GestureDetector(
                      onTap: onToggleDisponible,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: l.disponible ? AppColors.primaryLight : AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: l.disponible ? AppColors.primary : AppColors.border),
                        ),
                        child: Row(children: [
                          Icon(l.disponible ? Icons.toggle_on : Icons.toggle_off,
                              size: 16, color: l.disponible ? AppColors.primary : AppColors.textHint),
                          const SizedBox(width: 4),
                          Text(l.disponible ? 'Actif' : 'Inactif',
                              style: TextStyle(fontSize: 12,
                                  color: l.disponible ? AppColors.primary : AppColors.textHint,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 140, width: double.infinity,
    color: AppColors.primaryLight,
    child: const Icon(Icons.home, size: 48, color: AppColors.primary));
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: color)));
}

class _StatChip extends StatelessWidget {
  final IconData icon; final String value; final String label;
  const _StatChip({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: AppColors.textHint),
    const SizedBox(width: 3),
    Text('$value $label'.trim(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
  ]);
}

// ── Onglet "Statistiques" ─────────────────────────────────────
class _StatistiquesTab extends StatelessWidget {
  final String uid;
  const _StatistiquesTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: LogementService.getMesLogements(uid),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        final logements = docs.map((d) => Logement.fromMap(d.id, d.data() as Map<String, dynamic>)).toList();

        final totalVues = logements.fold<int>(0, (s, l) => s + l.nbVues);
        final nbActifs = logements.where((l) => l.disponible).length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Résumé', style: AppTextStyles.h2),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _StatCard(value: '${logements.length}', label: 'Annonces', icon: Icons.home_work, color: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(value: '$nbActifs', label: 'Actives', icon: Icons.check_circle, color: AppColors.success)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(value: '$totalVues', label: 'Vues totales', icon: Icons.visibility, color: AppColors.accent)),
            ]),
            const SizedBox(height: 20),
            Text('Performance par annonce', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            if (logements.isEmpty)
              const Text('Aucune annonce.', style: TextStyle(color: AppColors.textHint))
            else
              ...logements.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.titre, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${l.quartier}, ${l.ville}', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${l.nbVues} vues', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: l.disponible ? AppColors.primaryLight : AppColors.background,
                        borderRadius: BorderRadius.circular(4)),
                      child: Text(l.disponible ? 'Actif' : 'Inactif',
                        style: TextStyle(fontSize: 11, color: l.disponible ? AppColors.primary : AppColors.textHint))),
                  ]),
                ]),
              )),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value; final String label; final IconData icon; final Color color;
  const _StatCard({required this.value, required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center),
    ]));
}

// ============================================================
// PROFIL PRESTATAIRE — Onglet dédié
// ✅ Infos personnelles | Contacter le service client | Déconnexion
// ============================================================
class ProfilPrestataireScreen extends StatefulWidget {
  final UserModel? user;
  const ProfilPrestataireScreen({super.key, this.user});

  @override
  State<ProfilPrestataireScreen> createState() => _ProfilPrestataireScreenState();
}

class _ProfilPrestataireScreenState extends State<ProfilPrestataireScreen> {

  Future<void> _deconnecter() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter de votre espace prestataire ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    // Retour à la racine de l'app (splash / accueil visiteur)
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _contacterServiceClient() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Contacter le service client',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Notre équipe est disponible pour vous aider du lundi au vendredi, 8h–18h.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            _ContactOption(
              icon: Icons.email_outlined,
              label: 'Email',
              sublabel: 'support@sgkhome.cm',
              color: AppColors.primary,
              onTap: () async {
                final uri = Uri(scheme: 'mailto', path: 'support@sgkhome.cm',
                    query: 'subject=Aide prestataire');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            const SizedBox(height: 12),
            _ContactOption(
              icon: Icons.phone_outlined,
              label: 'Téléphone',
              sublabel: '+237 6XX XXX XXX',
              color: AppColors.success,
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: '+237600000000');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            const SizedBox(height: 12),
            _ContactOption(
              icon: Icons.chat_bubble_outline,
              label: 'WhatsApp',
              sublabel: 'Réponse rapide garantie',
              color: const Color(0xFF25D366),
              onTap: () async {
                final uri = Uri.parse('https://wa.me/237600000000');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _modifierProfil() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FormulaireModificationProfil(user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isDark = AppController.instance.isDark;

    return SingleChildScrollView(
      child: Column(
        children: [
          // ── En-tête avatar + nom ──────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      backgroundImage: (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                          ? NetworkImage(user.photoUrl!) as ImageProvider
                          : null,
                      child: (user?.photoUrl == null || user!.photoUrl!.isEmpty)
                          ? Text(
                              (user?.prenom.isNotEmpty == true ? user!.prenom[0] : '?').toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: GestureDetector(
                        onTap: _modifierProfil,
                        child: Container(
                          width: 28, height: 28,
                          decoration: const BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.edit, color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  user != null ? '${user.prenom} ${user.nom}'.trim() : 'Prestataire',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BadgeProfil(
                      label: user?.isVerifie == true ? '✓ Vérifié' : '⏳ Non vérifié',
                      bg: user?.isVerifie == true ? Colors.green.shade400 : Colors.orange.shade300,
                    ),
                    if (user?.isPremium == true) ...[
                      const SizedBox(width: 8),
                      _BadgeProfil(label: '★ Premium', bg: Colors.amber.shade400),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Mes informations ──────────────────────────────────
          _SectionProfil(
            title: 'MES INFORMATIONS',
            children: [
              _InfoRowProfil(icon: Icons.person_outline, label: 'Nom complet',
                  value: user != null ? '${user.prenom} ${user.nom}'.trim() : '—'),
              const Divider(indent: 56, height: 1),
              _InfoRowProfil(icon: Icons.email_outlined, label: 'Email', value: user?.email ?? '—'),
              const Divider(indent: 56, height: 1),
              _InfoRowProfil(icon: Icons.phone_outlined, label: 'Téléphone',
                  value: user?.telephone.isNotEmpty == true ? user!.telephone : 'Non renseigné'),
              const Divider(indent: 56, height: 1),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                ),
                title: const Text('Modifier mes informations',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                onTap: _modifierProfil,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Apparence ─────────────────────────────────────────
          _SectionProfil(
            title: 'APPARENCE',
            children: [
              SwitchListTile(
                secondary: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary, size: 20),
                ),
                title: const Text('Mode sombre', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                subtitle: Text(isDark ? 'Activé' : 'Désactivé',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                value: isDark,
                activeColor: AppColors.primary,
                onChanged: (_) => AppController.instance.toggleTheme(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Support ───────────────────────────────────────────
          _SectionProfil(
            title: 'ASSISTANCE',
            children: [
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.support_agent, color: Colors.blue, size: 20),
                ),
                title: const Text('Contacter le service client',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                subtitle: const Text('Email, téléphone, WhatsApp',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                onTap: _contacterServiceClient,
              ),
              const Divider(indent: 56, height: 1),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.help_outline, color: AppColors.primary, size: 20),
                ),
                title: const Text('Aide & FAQ',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                onTap: () {},
              ),
              const Divider(indent: 56, height: 1),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.privacy_tip_outlined, color: AppColors.primary, size: 20),
                ),
                title: const Text('Politique de confidentialité',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Déconnexion ───────────────────────────────────────
          _SectionProfil(
            title: 'COMPTE',
            children: [
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.logout, color: AppColors.error, size: 20),
                ),
                title: const Text('Se déconnecter',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: const Text('Quitter l\'espace prestataire',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                onTap: _deconnecter,
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text('ImmoConnect v1.0.0',
              style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────
class _SectionProfil extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionProfil({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(title,
              style: const TextStyle(
                  color: AppColors.textHint, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        Container(
          color: Theme.of(context).cardTheme.color,
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ── Ligne info ────────────────────────────────────────────────
class _InfoRowProfil extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRowProfil({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: AppColors.primary, size: 20),
    ),
    title: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    subtitle: Text(value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
  );
}

// ── Badge ─────────────────────────────────────────────────────
class _BadgeProfil extends StatelessWidget {
  final String label;
  final Color bg;
  const _BadgeProfil({required this.label, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

// ── Option contact ────────────────────────────────────────────
class _ContactOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  const _ContactOption({
    required this.icon, required this.label, required this.sublabel,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 15)),
          Text(sublabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        Icon(Icons.arrow_forward_ios, size: 14, color: color),
      ]),
    ),
  );
}

// ── Formulaire modification profil ───────────────────────────
class _FormulaireModificationProfil extends StatefulWidget {
  final UserModel? user;
  const _FormulaireModificationProfil({this.user});

  @override
  State<_FormulaireModificationProfil> createState() => _FormulaireModificationProfilState();
}

class _FormulaireModificationProfilState extends State<_FormulaireModificationProfil> {
  late final TextEditingController _prenomCtrl;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _telCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prenomCtrl = TextEditingController(text: widget.user?.prenom ?? '');
    _nomCtrl    = TextEditingController(text: widget.user?.nom ?? '');
    _telCtrl    = TextEditingController(text: widget.user?.telephone ?? '');
  }

  @override
  void dispose() {
    _prenomCtrl.dispose(); _nomCtrl.dispose(); _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final uid = widget.user?.id;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'prenom': _prenomCtrl.text.trim(),
        'nom': _nomCtrl.text.trim(),
        'telephone': _telCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profil mis à jour !'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Modifier mon profil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _prenomCtrl,
            decoration: const InputDecoration(labelText: 'Prénom', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nomCtrl,
            decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined),
                hintText: '+237 6XX XXX XXX'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _enregistrer,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
