// ============================================================
// FICHIER : lib/screens/dashboard_prestataire_screen.dart
// HOREM+ – Dashboard prestataire v6
// ✅ Onglets : Mes annonces | Messages | Statistiques | Profil
// ✅ Badge non-lus temps réel sur l'onglet Messages
// ✅ Profil prestataire dédié : infos, service client, déco
// ✅ Statistiques v2 : KPI cards, LineChart, BarChart (fl_chart)
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/geolocation_service.dart';
import '../services/logement_service.dart';
import '../services/storage_service.dart';
import '../app_controller.dart';
import '../l10n/app_localizations.dart';
import 'messagerie_screen.dart';

import 'paiement_publication_screen.dart';
import '../services/tarification_service.dart';
import '../services/paiement_service.dart';
import 'sponsorisation_screen.dart';
import 'publier_publicite_screen.dart';
import 'aide_faq_screen.dart';
import '../services/publicite_service.dart';
import '../widgets/shared_widgets.dart' as sw;
import '../services/notification_service.dart';

// ============================================================
// CONSTANTES DE TRADUCTION (valeur FR Firestore → clé i18n)
// ============================================================
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
  'École': 'type_ecole',
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
  late AppLocalizations _loc;

  final _formKey = GlobalKey<FormState>();
  final _titreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prixCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();

  String _typeLocation = 'location';
  String _typeBien = 'Studio';
  String _grade = 'standards';
  String _ville = 'Yaoundé';
  final List<String> _equipements = [];
  bool _isSubmitting = false;
  final _typeBienAutreCtrl = TextEditingController();

  // Heures d'ouverture (Pharmacie / Restaurant / Entreprise / École)
  final _heureOuvCtrl  = TextEditingController();
  final _heureFermCtrl = TextEditingController();

  // Jours de garde / ouverture (tous les types service)
  static const _joursLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  final List<String> _joursGarde = [];

  // Géolocalisation
  LatLng? _positionSelectionnee;
  String _adresseAffichee = '';
  bool _isLocating = false;
  GoogleMapController? _mapController;

  // Photos
  final List<XFile> _photosSelectionnees = [];
  final List<String> _photosExistantes = [];
  bool _isUploadingPhotos = false;

  // ── Immobilier vs. Service ────────────────────────────────────
  static const _typesImmo    = ['Studio', 'Appartement', 'Villa', 'Terrain', 'Bureau', 'Commerce'];
  static const _typesService = ['Pharmacie', 'Restaurant / Snack', 'Entreprise', 'École'];
  static const _typeAutre    = 'Autre';

  final List<String> _villes = ['Yaoundé', 'Douala', 'Bafoussam', 'Garoua', 'Maroua'];

  bool get _isServiceType    => _typesService.contains(_typeBien);
  bool get _isImmoType       => _typesImmo.contains(_typeBien);
  bool get _isPharmacieType  => _typeBien == 'Pharmacie';
  bool get _isRestaurantType => _typeBien == 'Restaurant / Snack';
  bool get _isEntrepriseType => _typeBien == 'Entreprise';
  bool get _isEcoleType      => _typeBien == 'École';
  bool get _isAutreType      => _typeBien == _typeAutre;
  // Types qui paient la visibilité annuelle (pas la commission %)
  bool get _isVisibiliteType => _isRestaurantType || _isEntrepriseType || _isEcoleType;

  // Valeur Firestore pour le type : si Autre, utilise le texte libre
  String get _typeBienFirestore =>
      _isAutreType && _typeBienAutreCtrl.text.trim().isNotEmpty
          ? _typeBienAutreCtrl.text.trim()
          : _typeBien;

  // Grade automatique selon le type de bien
  String get _gradeEffectif {
    if (_isPharmacieType)  return 'pharmacie';
    if (_isRestaurantType) return 'restaurant';
    if (_isEntrepriseType) return 'entreprise';
    if (_isEcoleType)      return 'ecole';
    if (_isAutreType)      return 'standards';
    return _grade;
  }
  final List<String> _equipementsDispos = [
    'Meublé', 'Wifi', 'Climatiseur', 'Eau chaude',
    'Gardien', 'Parking', 'Groupe électrogène', 'Titre foncier'
  ];

  static const LatLng _yaoundeCenter = LatLng(3.8480, 11.5021);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

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
      _grade = l.grade;
      _ville = l.ville;
      _equipements.addAll(l.equipements);
      _photosExistantes.addAll(l.photos);
      _heureOuvCtrl.text  = l.heureOuverture ?? '';
      _heureFermCtrl.text = l.heureFermeture ?? '';
      _joursGarde.addAll(l.joursGarde);
      if (l.latitude != 0 && l.longitude != 0) {
        _positionSelectionnee = LatLng(l.latitude, l.longitude);
        _adresseAffichee = '${l.quartier}, ${l.ville}';
      }
      // Si type non connu → "Autre"
      final connu = [..._typesImmo, ..._typesService];
      if (!connu.contains(l.typeBien)) {
        _typeBien = _typeAutre;
        _typeBienAutreCtrl.text = l.typeBien;
      }
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose(); _descCtrl.dispose(); _prixCtrl.dispose();
    _surfaceCtrl.dispose(); _quartierCtrl.dispose();
    _heureOuvCtrl.dispose(); _heureFermCtrl.dispose();
    _typeBienAutreCtrl.dispose();
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
            SnackBar(content: Text(_loc.t('form_gps_error')), backgroundColor: AppColors.error));
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
    setState(() { _positionSelectionnee = position; _adresseAffichee = _loc.t('form_loading_address'); });
    final adresse = await GeolocationService.getAddressFromCoordinates(position.latitude, position.longitude);
    if (mounted) setState(() => _adresseAffichee = adresse);
  }

  Future<void> _publier() async {
    if (!_formKey.currentState!.validate()) return;
    if (_positionSelectionnee == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_loc.t('form_no_position')),
          backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception(_loc.t('form_not_connected'));

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

      final prix = (_isPharmacieType || _isVisibiliteType)
          ? 0.0
          : (double.tryParse(_prixCtrl.text) ?? 0);
      final estNouvelle = widget.logement == null;

      final prestataire = AuthService.instance.currentUser;
      final data = {
        'titre': _titreCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'prix': prix,
        'surface': int.tryParse(_surfaceCtrl.text) ?? 0,
        'quartier': _quartierCtrl.text.trim(),
        'ville': _ville,
        'typeLocation': _isServiceType ? 'service' : _typeLocation,
        'typeBien': _typeBienFirestore,
        'grade': _gradeEffectif,
        'equipements': _equipements,
        'latitude': _positionSelectionnee!.latitude,
        'longitude': _positionSelectionnee!.longitude,
        'photos': photoUrls,
        'uid_prestataire': uid,
        'prestatireId': uid,
        'prestatireNom': prestataire != null
            ? '${prestataire.prenom} ${prestataire.nom}'.trim()
            : '',
        'prestatirePhone': prestataire?.telephone ?? '',
        'isSponsored': false,
        if (_heureOuvCtrl.text.trim().isNotEmpty)
          'heureOuverture': _heureOuvCtrl.text.trim(),
        if (_heureFermCtrl.text.trim().isNotEmpty)
          'heureFermeture': _heureFermCtrl.text.trim(),
        if (_joursGarde.isNotEmpty) 'joursGarde': _joursGarde,
      };

      if (!estNouvelle) {
        // Édition : pas de paiement requis
        await LogementService.updateLogement(widget.logement!.id, data);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_loc.t('form_updated_ok')),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
        }
        return;
      }

      // ─── Pharmacie → publication directement gratuite ─────────────────────
      if (_isPharmacieType) {
        await LogementService.addLogement({
          ...data,
          'disponible': true,
          'visibleAdmin': false,
          'paymentPending': false,
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_loc.t('form_published_ok')),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
        }
        return;
      }

      // ─── Création brouillon + écran de paiement ───────────────────────────
      final brouillonId = await LogementService.addLogement({
        ...data,
        'disponible': false,
        'visibleAdmin': true,
        'paymentPending': true,
      });

      int montant;
      String titreEcran;
      String dureeLabel;
      InitierPaiementCb initierCb;

      if (_isVisibiliteType) {
        // Visibilité annuelle Entreprise / Restaurant / École
        montant = TarificationService.montantVisibilite(_typeBienFirestore);
        titreEcran = 'Visibilité annuelle';
        dureeLabel = 'Votre fiche sera visible pendant 1 an sur Horem+.';
        initierCb = ({required String telephone, required String operateur}) =>
            PaiementService.instance.initierVisibilite(
              logementId: brouillonId,
              telephone: telephone,
              channel: operateur,
            );
      } else {
        // Immobilier → commission % du prix du bien, visible 1 mois
        final prixBien = double.tryParse(_prixCtrl.text) ?? 0;
        final gradeEnum = GradeBienLabel.fromCode(_gradeEffectif);
        montant = TarificationService.instance.montantSponsorisation(
          grade: gradeEnum,
          typeBien: _typeBienFirestore,
          prixBien: prixBien,
        );
        titreEcran = 'Frais de publication';
        dureeLabel = 'Votre annonce sera visible pendant 1 mois sur Horem+.';
        initierCb = ({required String telephone, required String operateur}) =>
            PaiementService.instance.initierPublication(
              logementId: brouillonId,
              telephone: telephone,
              channel: operateur,
              montant: montant,
            );
      }

      if (!mounted) return;
      final paye = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaiementPublicationScreen(
            logementId: brouillonId,
            titreAnnonce: _titreCtrl.text.trim(),
            montant: montant,
            titreEcran: titreEcran,
            dureeLabel: dureeLabel,
            initierPersonnalise: initierCb,
            boutonLabel: _isVisibiliteType
                ? 'Payer et activer la visibilité'
                : 'Payer et publier l\'annonce',
            succesMessage: _isVisibiliteType
                ? 'Votre fiche est maintenant visible pendant 1 an sur Horem+.'
                : 'Votre annonce est publiée et visible pendant 1 mois sur Horem+.',
          ),
        ),
      );

      if (paye == true) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_loc.t('form_published_ok')),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
        }
      } else {
        // Paiement annulé/échoué → supprimer le brouillon
        try {
          await LogementService.deleteLogement(brouillonId);
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Publication annulée : aucun paiement validé.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ));
        }
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
      appBar: AppBar(title: Text(widget.logement == null ? _loc.t('dashboard_new_listing') : _loc.t('dashboard_edit_listing'))),
      body: sw.SkylineBackground(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.black : Colors.white).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_loc.t('form_photos'), style: AppTextStyles.h3),
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
                          decoration: BoxDecoration(color: context.appBackground, borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.appBorder)),
                          child: const Center(child: CircularProgressIndicator())),
                  ]),
                ),
              const SizedBox(height: 8),
              if (totalPhotos < 6)
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _choisirPhotos,
                      icon: const Icon(Icons.photo_library), label: Text(_loc.t('form_gallery')))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _prendrePhoto,
                      icon: const Icon(Icons.camera_alt), label: Text(_loc.t('form_camera')))),
                ]),
              Text('$totalPhotos/6 photos', style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 20),
              Text(_loc.t('form_title_field'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _titreCtrl,
                  decoration: InputDecoration(hintText: _loc.t('form_title_hint')),
                  validator: (v) => v!.isEmpty ? _loc.t('form_required') : null),
              const SizedBox(height: 16),
              // ── Type de bien ──────────────────────────────────
              Text(_loc.t('form_type_bien'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _typeBien,
                  items: [
                    DropdownMenuItem(
                      value: null, enabled: false,
                      child: Text(_loc.t('form_immo_group'),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
                    ),
                    ..._typesImmo.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                    DropdownMenuItem(
                      value: null, enabled: false,
                      child: Text(_loc.t('form_service_group'),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 13)),
                    ),
                    ..._typesService.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                    const DropdownMenuItem(
                      value: null, enabled: false,
                      child: Divider(height: 1),
                    ),
                    DropdownMenuItem(
                      value: _typeAutre,
                      child: Text(_loc.t('form_type_autre')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() { _typeBien = v; });
                  }),

              // ── Champ libre si "Autre" ────────────────────────
              if (_isAutreType) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _typeBienAutreCtrl,
                  decoration: InputDecoration(
                    labelText: _loc.t('form_type_autre_label'),
                    hintText: _loc.t('form_type_autre_hint'),
                    prefixIcon: const Icon(Icons.edit_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? _loc.t('form_required') : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],

              // ── Type de transaction (immobilier uniquement) ───
              if (_isImmoType) ...[
                const SizedBox(height: 16),
                Text(_loc.t('form_transaction_type'), style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _ChoixCard(label: _loc.t('form_location'), icon: Icons.home_work,
                      selected: _typeLocation == 'location',
                      onTap: () => setState(() => _typeLocation = 'location'))),
                  const SizedBox(width: 12),
                  Expanded(child: _ChoixCard(label: _loc.t('form_sale'), icon: Icons.sell,
                      selected: _typeLocation == 'vente',
                      onTap: () => setState(() => _typeLocation = 'vente'))),
                ]),
              ],

              // ── Catégorie / Standing (immobilier uniquement) ──
              if (_isImmoType) ...[
                const SizedBox(height: 16),
                Text(_loc.t('form_standing'), style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  _loc.t('form_standing_desc'),
                  style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _grade,
                  items: [
                    DropdownMenuItem(value: 'standards',    child: Text(_loc.t('form_grade_standard'))),
                    DropdownMenuItem(value: 'haut_standing', child: Text(_loc.t('form_grade_haut'))),
                    DropdownMenuItem(value: 'meubles',      child: Text(_loc.t('form_grade_meuble'))),
                    DropdownMenuItem(value: 'a_louer',      child: Text(_loc.t('form_grade_a_louer'))),
                  ],
                  onChanged: (v) => setState(() => _grade = v!),
                ),
              ],

              // ── Badge info pour les types service ─────────────
              if (_isServiceType) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isPharmacieType
                        ? Colors.green.shade50
                        : _isRestaurantType
                            ? Colors.orange.shade50
                            : _isEcoleType
                                ? Colors.purple.shade50
                                : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isPharmacieType
                          ? Colors.green.shade200
                          : _isRestaurantType
                              ? Colors.orange.shade200
                              : _isEcoleType
                                  ? Colors.purple.shade200
                                  : Colors.blue.shade200,
                    ),
                  ),
                  child: Row(children: [
                    Text(
                      _isPharmacieType ? '💊'
                          : _isRestaurantType ? '🍽️'
                          : _isEcoleType ? '🎓'
                          : '🏢',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _isPharmacieType
                          ? _loc.t('form_pharma_info')
                          : _isRestaurantType
                              ? _loc.t('form_resto_info')
                              : _isEcoleType
                                  ? _loc.t('form_ecole_info')
                                  : _loc.t('form_entreprise_info'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _isPharmacieType
                            ? Colors.green.shade800
                            : _isRestaurantType
                                ? Colors.orange.shade800
                                : _isEcoleType
                                    ? Colors.purple.shade800
                                    : Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    )),
                  ]),
                ),
              ],

              const SizedBox(height: 16),
              Text(_loc.t('form_city'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _ville,
                  items: _villes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => _ville = v!)),
              const SizedBox(height: 16),
              Text(_loc.t('form_neighborhood'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _quartierCtrl,
                  decoration: InputDecoration(hintText: _loc.t('form_neighborhood_hint')),
                  validator: (v) => v!.isEmpty ? _loc.t('form_required') : null),

              // ── Prix (masqué pour pharmacie et types visibilité) ──────────
              if (!_isPharmacieType && !_isVisibiliteType) ...[
                const SizedBox(height: 16),
                Text(_loc.t('form_price'), style: AppTextStyles.h3),
                const SizedBox(height: 8),
                TextFormField(controller: _prixCtrl, keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        hintText: _loc.t('form_price_hint'),
                        suffixText: _isImmoType && _typeLocation == 'location'
                            ? 'XAF/mois'
                            : 'XAF'),
                    validator: (v) => (!_isServiceType && (v == null || v.isEmpty))
                        ? _loc.t('form_required')
                        : null),
              ],

              // ── Heures d'ouverture (tous les types service) ───
              if (_isServiceType) ...[
                const SizedBox(height: 16),
                Text(_loc.t('form_opening_hours'), style: AppTextStyles.h3),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _heureOuvCtrl,
                    decoration: InputDecoration(
                        labelText: _loc.t('form_opening_time'),
                        hintText: '08:00',
                        prefixIcon: const Icon(Icons.schedule)),
                    keyboardType: TextInputType.datetime,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _heureFermCtrl,
                    decoration: InputDecoration(
                        labelText: _loc.t('form_closing_time'),
                        hintText: '22:00',
                        prefixIcon: const Icon(Icons.schedule_outlined)),
                    keyboardType: TextInputType.datetime,
                  )),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_loc.t('form_time_format'),
                      style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                ),
              ],

              // ── Jours de garde / d'ouverture (types service) ──
              if (_isServiceType) ...[
                const SizedBox(height: 16),
                Text(
                  _isPharmacieType
                      ? _loc.t('form_jours_garde')
                      : _loc.t('form_jours_ouverture'),
                  style: AppTextStyles.h3,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _joursLabels.map((j) {
                    final sel = _joursGarde.contains(j);
                    return FilterChip(
                      label: Text(j, style: const TextStyle(fontSize: 13)),
                      selected: sel,
                      selectedColor: context.appPrimaryLight,
                      checkmarkColor: AppColors.primary,
                      onSelected: (v) => setState(() =>
                          v ? _joursGarde.add(j) : _joursGarde.remove(j)),
                    );
                  }).toList(),
                ),
              ],

              // ── Surface (immobilier uniquement) ───────────────
              if (_isImmoType) ...[
                const SizedBox(height: 16),
                Text(_loc.t('form_surface'), style: AppTextStyles.h3),
                const SizedBox(height: 8),
                TextFormField(controller: _surfaceCtrl, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Ex: 45', suffixText: 'm²')),
              ],
              const SizedBox(height: 16),
              Text(_loc.t('form_description'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(controller: _descCtrl, maxLines: 4,
                  decoration: InputDecoration(hintText: _loc.t('form_desc_hint')),
                  validator: (v) => v!.isEmpty ? _loc.t('form_required') : null),
              const SizedBox(height: 16),
              Text(_loc.t('form_equipment'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                  children: _equipementsDispos.map((eq) {
                    final sel = _equipements.contains(eq);
                    return FilterChip(label: Text(_loc.t(_equipKeys[eq] ?? eq)), selected: sel,
                        selectedColor: context.appPrimaryLight, checkmarkColor: AppColors.primary,
                        onSelected: (v) => setState(() => v ? _equipements.add(eq) : _equipements.remove(eq)));
                  }).toList()),
              const SizedBox(height: 20),
              Text(_loc.t('form_localization'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                  onPressed: _isLocating ? null : _localiserMaintenant,
                  icon: _isLocating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.my_location),
                  label: Text(_isLocating ? _loc.t('form_detecting') : _loc.t('form_gps_btn')),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44))),
              const SizedBox(height: 8),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: _positionSelectionnee != null ? context.appPrimaryLight : context.appBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _positionSelectionnee != null ? AppColors.primary : context.appBorder)),
                  child: Row(children: [
                    Icon(_positionSelectionnee != null ? Icons.location_on : Icons.location_off,
                        color: _positionSelectionnee != null ? AppColors.primary : AppColors.textHint, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_adresseAffichee.isEmpty ? _loc.t('form_gps_btn') : _adresseAffichee,
                          style: TextStyle(color: _positionSelectionnee != null ? AppColors.primary : context.appTextHint, fontSize: 13)),
                      if (_positionSelectionnee != null)
                        Text('Lat: ${_positionSelectionnee!.latitude.toStringAsFixed(5)} · Lng: ${_positionSelectionnee!.longitude.toStringAsFixed(5)}',
                            style: TextStyle(color: context.appTextSecondary, fontSize: 11)),
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
                          infoWindow: InfoWindow(title: _titreCtrl.text.isNotEmpty ? _titreCtrl.text : _loc.t('form_my_place')))} : {},
                      myLocationButtonEnabled: false, zoomControlsEnabled: false))),
              const SizedBox(height: 4),
              Text(_loc.t('form_map_hint'),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              if (_positionSelectionnee == null)
                Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(_loc.t('form_location_required'),
                        style: const TextStyle(color: AppColors.error, fontSize: 12))),
              const SizedBox(height: 32),
              ElevatedButton(
                  onPressed: _isSubmitting ? null : _publier,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: _isSubmitting
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(_isUploadingPhotos ? _loc.t('form_uploading') : _loc.t('form_publishing')),
                  ])
                      : Text(widget.logement == null ? _loc.t('form_publish_btn') : _loc.t('form_save_changes'))),
              const SizedBox(height: 40),
            ],
          ),
          ),
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
  Widget build(BuildContext context) => _buildThumb(child: Image.network(url, fit: BoxFit.cover), onDelete: onDelete, context: context);
}

class _PhotoThumbLocal extends StatelessWidget {
  final String path; final VoidCallback onDelete;
  const _PhotoThumbLocal({required this.path, required this.onDelete});
  @override
  Widget build(BuildContext context) => Stack(children: [
    _buildThumb(child: Image.asset(path, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image)), onDelete: onDelete, context: context),
    Positioned(bottom: 4, left: 4, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
        child: Text(AppLocalizations.of(context).t('common_new'), style: const TextStyle(color: Colors.white, fontSize: 9))))
  ]);
}

Widget _buildThumb({required Widget child, required VoidCallback onDelete, required BuildContext context}) {
  return Stack(children: [
    Container(width: 90, height: 90, margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: context.appBackground),
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
              color: selected ? AppColors.primary : context.appBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.primary : context.appBorder, width: 1.5)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected ? Colors.white : context.appTextSecondary, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: selected ? Colors.white : context.appTextSecondary, fontWeight: FontWeight.w600)),
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
  late AppLocalizations _loc;
  late TabController _tabController;

  static const _langues = [
    {'code': 'fr', 'label': 'Français', 'flag': '🇫🇷'},
    {'code': 'en', 'label': 'English', 'flag': '🇬🇧'},
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
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
          Text(_loc.t('profil_choose_language'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
        title: Text(_loc.t('dashboard_my_space'), maxLines: 2, style: const TextStyle(height: 1.2)),
        toolbarHeight: 64,
        actions: [
          IconButton(
            tooltip: isDark ? _loc.t('dashboard_tooltip_light') : _loc.t('dashboard_tooltip_dark'),
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => AppController.instance.toggleTheme(),
          ),
          GestureDetector(
            onTap: () => _changerLangue(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(flagEmoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FormulaireAnnonce()),
              ),
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
              label: Text(
                _loc.t('dashboard_new_listing'),
                style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.2),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.list_alt), text: _loc.t('dashboard_tab_listings')),
            Tab(
              child: StreamBuilder<QuerySnapshot>(
                stream: uid.isEmpty
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                    .collection('conversations')
                    .where('participants', arrayContains: uid)
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
                            _loc.t('dashboard_tab_msgs'),
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
            Tab(icon: const Icon(Icons.bar_chart), text: _loc.t('dashboard_tab_stats')),
            Tab(icon: const Icon(Icons.campaign_outlined), text: _loc.t('dashboard_tab_pubs')),
            Tab(icon: const Icon(Icons.person), text: _loc.t('dashboard_tab_profil')),
          ],
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
      body: sw.SkylineBackground(
        child: Column(
          children: [
            _ProfilPrestataireHeader(user: user),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MesAnnoncesTab(uid: uid),
                  MessagerieScreen(forceUid: uid),
                  _StatistiquesTab(uid: uid),
                  _MesPublicitesTab(uid: uid),
                  ProfilPrestataireScreen(user: user),
                ],
              ),
            ),
          ],
        ),
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
                  user!.email ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (user!.isVerifie)
                  _BadgeDash(
                    label: AppLocalizations.of(context).t('prest_header_verified'),
                    color: Colors.green.shade400,
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
class _MesAnnoncesTab extends StatefulWidget {
  final String uid;
  const _MesAnnoncesTab({required this.uid});

  @override
  State<_MesAnnoncesTab> createState() => _MesAnnoncesTabState();
}

class _MesAnnoncesTabState extends State<_MesAnnoncesTab> {
  late AppLocalizations _loc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: LogementService.getMesLogements(widget.uid),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_work_outlined, size: 64, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(_loc.t('dashboard_no_listings'),
                    style: const TextStyle(fontSize: 16, color: Colors.white)),
                const SizedBox(height: 8),
                Text(_loc.t('dashboard_no_listings_hint'),
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
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
            onDelete: () => _confirmerSuppression(logements[i].id),
            onToggleDisponible: () => _toggleDisponible(logements[i]),
          ),
        );
      },
    );
  }

  Future<void> _confirmerSuppression(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(_loc.t('dashboard_delete_confirm_title'))),
        ]),
        content: Text(_loc.t('dashboard_delete_confirm_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_loc.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_loc.t('common_delete')),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await LogementService.deleteLogement(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.t('dashboard_deleted_ok')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la suppression : $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleDisponible(Logement l) async {
    if (!l.visibleAdmin && !l.disponible) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).t('admin_visibility_required')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }
      return;
    }
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

  // Zone sponsorisation : badge si actif, sinon bouton "Sponsoriser".
  // Masquée pour les pharmacies (publication gratuite, pas de sponsoring).
  Widget _buildSponsorZone(BuildContext context) {
    final l = logement;
    if (l.typeBien == 'Pharmacie') return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    if (l.estSponsorie) {
      final until = l.sponsoredUntil;
      final dateStr = until != null
          ? '${until.day.toString().padLeft(2, '0')}/${until.month.toString().padLeft(2, '0')}/${until.year}'
          : null;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Text('🌟', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              dateStr != null ? '${loc.t('dashboard_sponsored_until')} $dateStr' : loc.t('dashboard_sponsored'),
              style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SponsorisationScreen(
              logementId: l.id,
              titre: l.titre,
              photo: l.photos.isNotEmpty ? l.photos.first : null,
            ),
          ),
        ),
        icon: const Text('🚀', style: TextStyle(fontSize: 14)),
        label: Text(loc.t('dashboard_sponsor_btn')),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = logement;
    final loc = AppLocalizations.of(context);
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
                    color: !l.visibleAdmin ? AppColors.warning : l.disponible ? AppColors.success : AppColors.textHint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(!l.visibleAdmin ? loc.t('admin_pending_approval')
                      : l.disponible ? loc.t('dashboard_listing_available') : loc.t('dashboard_listing_unavailable'),
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
                      style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  Text(l.prixLabel,
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatChip(icon: Icons.visibility_outlined, value: '${l.nbVues}', label: 'vues'),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.people_outline, value: loc.t(_typeBienKeys[l.typeBien] ?? l.typeBien), label: ''),
                    const Spacer(),
                    GestureDetector(
                      onTap: onToggleDisponible,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: l.disponible ? context.appPrimaryLight : context.appBackground,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: l.disponible ? AppColors.primary : context.appBorder),
                        ),
                        child: Row(children: [
                          Icon(l.disponible ? Icons.toggle_on : Icons.toggle_off,
                              size: 16, color: l.disponible ? AppColors.primary : AppColors.textHint),
                          const SizedBox(width: 4),
                          Text(l.disponible ? loc.t('dashboard_listing_active') : loc.t('dashboard_listing_inactive'),
                              style: TextStyle(fontSize: 12,
                                  color: l.disponible ? AppColors.primary : AppColors.textHint,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildPublicationZone(context),
                const SizedBox(height: 8),
                _buildSponsorZone(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationZone(BuildContext context) {
    final l = logement;
    if (l.typeBien == 'Pharmacie') return const SizedBox.shrink();
    if (l.paymentPending) return const SizedBox.shrink();

    final expiry = l.publicationExpiry;
    if (expiry == null) return const SizedBox.shrink();

    final expiree = l.estPublicationExpiree;
    final dateStr = '${expiry.day.toString().padLeft(2, '0')}/${expiry.month.toString().padLeft(2, '0')}/${expiry.year}';

    if (expiree) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.schedule, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Publication expirée le $dateStr — priorité réduite',
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Active jusqu\'au $dateStr',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      height: 140, width: double.infinity,
      color: context.appPrimaryLight,
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
    Text('$value $label'.trim(), style: const TextStyle(fontSize: 12)),
  ]);
}

// ============================================================
// ONGLET STATISTIQUES — Version complète avec fl_chart
// ============================================================
class _StatistiquesTab extends StatefulWidget {
  final String uid;
  const _StatistiquesTab({required this.uid});

  @override
  State<_StatistiquesTab> createState() => _StatistiquesTabState();
}

class _StatistiquesTabState extends State<_StatistiquesTab> {
  late AppLocalizations _loc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  // ── Palette ──────────────────────────────────────────────────
  static const Color _bleu = Color(0xFF0071C2);
  static const Color _bleuClair = Color(0xFFE8F4FD);
  static const Color _bleuMoyen = Color(0xFF5BA8D9);
  static const Color _orange = Color(0xFFF97316);
  static const Color _ombre = Color(0x0D000000);

  // ── État ─────────────────────────────────────────────────────
  bool _loading = true;
  String? _erreur;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _evolution = [];

  // Index de la barre surlignée dans le BarChart
  int _touchedBarIndex = -1;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  Future<void> _chargerDonnees() async {
    setState(() { _loading = true; _erreur = null; });
    try {
      final stats = await LogementService.getStatistiquesPrestataire(widget.uid);

      // Évolution des 7 derniers jours — on prend la meilleure annonce ou agrège
      List<Map<String, dynamic>> evo = [];
      final vuesParAnnonce = stats['vuesParAnnonce'] as List<Map<String, dynamic>>? ?? [];
      if (vuesParAnnonce.isNotEmpty) {
        evo = await LogementService.getEvolutionVues(
            vuesParAnnonce.first['id'] as String, 7);
      } else {
        // Aucune annonce — liste vide
        evo = [];
      }

      if (mounted) {
        setState(() {
          _stats = stats;
          _evolution = evo;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _erreur = e.toString(); _loading = false; });
    }
  }

  // ── Build principal ───────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _bleu),
            const SizedBox(height: 16),
            Text(_loc.t('stats_loading'),
                style: TextStyle(color: context.appTextSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('${_loc.t('common_error')} : $_erreur',
                  style: TextStyle(color: context.appTextSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _chargerDonnees,
                icon: const Icon(Icons.refresh),
                label: Text(_loc.t('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final s = _stats!;
    final totalVues = s['totalVues'] as int? ?? 0;
    final totalContacts = s['totalContacts'] as int? ?? 0;
    final totalAnnonces = s['totalAnnonces'] as int? ?? 0;
    final taux = s['tauxConversion'] as double? ?? 0.0;
    final meilleur = s['meilleurAnnonce'] as Map<String, dynamic>?;
    final parAnnonce = s['vuesParAnnonce'] as List<Map<String, dynamic>>? ?? [];

    // ── État vide ─────────────────────────────────────────────
    if (totalAnnonces == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.appPrimaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bar_chart_rounded, size: 48, color: _bleu),
              ),
              const SizedBox(height: 20),
              Text(_loc.t('stats_no_data'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                _loc.t('stats_no_data_hint'),
                style: const TextStyle(fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FormulaireAnnonce())),
                icon: const Icon(Icons.add),
                label: Text(_loc.t('stats_create_btn')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bleu,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Contenu principal ────────────────────────────────────
    return RefreshIndicator(
      color: _bleu,
      onRefresh: _chargerDonnees,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Titre section ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_loc.t('stats_dashboard'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(_loc.t('stats_overview'),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              // Bouton refresh
              GestureDetector(
                onTap: _chargerDonnees,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.appPrimaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.refresh, color: _bleu, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── (a) BANDEAU KPI 2×2 ────────────────────────────
          _buildKpiGrid(
            totalVues: totalVues,
            totalContacts: totalContacts,
            taux: taux,
            totalAnnonces: totalAnnonces,
          ),
          const SizedBox(height: 24),

          // ── (b) GRAPHIQUE COURBE ────────────────────────────
          if (_evolution.isNotEmpty) ...[
            _buildSectionHeader(_loc.t('stats_section_7d'),
                icon: Icons.show_chart_rounded),
            const SizedBox(height: 12),
            _buildLineChart(),
            const SizedBox(height: 24),
          ],

          // ── (c) GRAPHIQUE BARRES ────────────────────────────
          if (parAnnonce.isNotEmpty) ...[
            _buildSectionHeader(_loc.t('stats_section_perfs'),
                icon: Icons.bar_chart_rounded),
            const SizedBox(height: 6),
            Text(_loc.t('stats_views_hint'),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
            const SizedBox(height: 12),
            _buildBarChart(parAnnonce),
            const SizedBox(height: 8),
            _buildLegende(),
            const SizedBox(height: 24),
          ],

          // ── (d) MEILLEURE ANNONCE ───────────────────────────
          if (meilleur != null) ...[
            _buildSectionHeader(_loc.t('stats_best_section'), icon: Icons.star_rounded),
            const SizedBox(height: 12),
            _buildMeilleureAnnonceCard(meilleur),
            const SizedBox(height: 24),
          ],

          // ── (e) BOUTON PDF (MVP — SnackBar) ─────────────────
          _buildBoutonRapport(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // WIDGETS PRIVÉS
  // ──────────────────────────────────────────────────────────────

  /// Titre de section avec icône
  Widget _buildSectionHeader(String titre, {required IconData icon}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: _bleu, size: 18),
        ),
        const SizedBox(width: 10),
        Text(titre,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }

  /// Grille 2×2 des KPI
  Widget _buildKpiGrid({
    required int totalVues,
    required int totalContacts,
    required double taux,
    required int totalAnnonces,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _KpiCard(
          emoji: '👁',
          label: _loc.t('stats_kpi_views'),
          value: _formatNombre(totalVues),
          color: _bleu,
          bgColor: _bleuClair,
        ),
        _KpiCard(
          emoji: '💬',
          label: _loc.t('stats_kpi_contacts'),
          value: _formatNombre(totalContacts),
          color: const Color(0xFF059669),
          bgColor: const Color(0xFFECFDF5),
        ),
        _KpiCard(
          emoji: '📊',
          label: _loc.t('stats_kpi_conversion'),
          value: '${taux.toStringAsFixed(1)} %',
          color: _orange,
          bgColor: const Color(0xFFFFF7ED),
        ),
        _KpiCard(
          emoji: '🏠',
          label: _loc.t('stats_kpi_listings'),
          value: '$totalAnnonces',
          color: const Color(0xFF7C3AED),
          bgColor: const Color(0xFFF5F3FF),
        ),
      ],
    );
  }

  /// LineChart fl_chart — évolution des vues sur 7 jours
  Widget _buildLineChart() {
    if (_evolution.isEmpty) return const SizedBox.shrink();
    // Capturer les couleurs adaptatives ici car les callbacks fl_chart n'ont pas de BuildContext
    final hintColor = context.appTextHint;
    final secondaryColor = context.appTextSecondary;

    final spots = _evolution.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value['vues'] as int).toDouble());
    }).toList();

    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);
    final paddedMax = maxY < 5 ? 10.0 : maxY * 1.25;

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: _ombre, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (_evolution.length - 1).toDouble(),
          minY: 0,
          maxY: paddedMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: paddedMax / 4,
            getDrawingHorizontalLine: (v) => const FlLine(
              color: Color(0xFFE5E7EB),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: paddedMax / 4,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: hintColor),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= _evolution.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _evolution[i]['jour'] as String,
                      style: TextStyle(fontSize: 11, color: secondaryColor,
                          fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _bleu,
              tooltipRoundedRadius: 8,
              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                '${s.y.toInt()} ${_loc.t('stats_tooltip_views')}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
              )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: _bleu,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3.5,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: _bleu,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [_bleu.withValues(alpha: 0.18), _bleu.withValues(alpha: 0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// BarChart fl_chart — vues vs contacts par annonce
  Widget _buildBarChart(List<Map<String, dynamic>> parAnnonce) {
    final hintColor2 = context.appTextHint;
    final secondaryColor2 = context.appTextSecondary;
    final maxVal = parAnnonce.fold<int>(
        0, (m, a) => (a['vues'] as int) > m ? (a['vues'] as int) : m);
    final paddedMax = maxVal < 5 ? 10.0 : maxVal * 1.3;

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: _ombre, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: BarChart(
        BarChartData(
          maxY: paddedMax,
          barTouchData: BarTouchData(
            touchCallback: (event, response) {
              if (response?.spot != null && event.isInterestedForInteractions) {
                setState(() => _touchedBarIndex =
                    response!.spot!.touchedBarGroupIndex);
              } else {
                setState(() => _touchedBarIndex = -1);
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              tooltipRoundedRadius: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final annonce = parAnnonce[groupIndex];
                final label = rodIndex == 0 ? _loc.t('stats_chart_views') : _loc.t('stats_chart_contacts');
                return BarTooltipItem(
                  '${annonce['titre']}\n$label : ${rod.toY.toInt()}',
                  const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w500),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= parAnnonce.length) return const SizedBox.shrink();
                  final titre = parAnnonce[i]['titre'] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      titre.length > 6 ? '${titre.substring(0, 5)}…' : titre,
                      style: TextStyle(fontSize: 9, color: secondaryColor2),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: paddedMax / 4,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(fontSize: 10, color: hintColor2),
                ),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: paddedMax / 4,
            getDrawingHorizontalLine: (v) => const FlLine(
              color: Color(0xFFE5E7EB),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: parAnnonce.asMap().entries.map((e) {
            final i = e.key;
            final a = e.value;
            final isTouched = i == _touchedBarIndex;
            final vues = (a['vues'] as int).toDouble();
            final contacts = (a['contacts'] as int).toDouble();
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: vues,
                  color: isTouched ? _bleu : _bleuMoyen,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: contacts.toDouble(),
                  color: isTouched ? _orange : _orange.withValues(alpha: 0.7),
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
              barsSpace: 4,
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Légende Vues / Contacts pour le BarChart
  Widget _buildLegende() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendeDot(color: _bleuMoyen, label: _loc.t('stats_chart_views')),
        const SizedBox(width: 20),
        _LegendeDot(color: _orange, label: _loc.t('stats_chart_contacts')),
      ],
    );
  }

  /// Carte "Meilleure annonce"
  Widget _buildMeilleureAnnonceCard(Map<String, dynamic> meilleur) {
    final titre = meilleur['titre'] as String? ?? 'Annonce';
    final vues = meilleur['vues'] as int? ?? 0;
    final contacts = meilleur['contacts'] as int? ?? 0;
    final photoUrl = meilleur['photoUrl'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: _ombre, blurRadius: 8, offset: Offset(0, 2))],
        border: Border.all(color: _bleu.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Photo miniature
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
              photoUrl,
              width: 72, height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _MiniPhotoPlaceholder(),
            )
                : _MiniPhotoPlaceholder(),
          ),
          const SizedBox(width: 14),
          // Textes
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge ⭐
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_loc.t('stats_best_badge'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: Color(0xFF854D0E))),
                ),
                const SizedBox(height: 6),
                Text(titre,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.visibility_outlined, size: 14, color: _bleu),
                  const SizedBox(width: 4),
                  Text('$vues ${_loc.t('stats_tooltip_views')}',
                      style: const TextStyle(color: _bleu, fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Text('$contacts ${_loc.t('stats_chart_contacts').toLowerCase()}',
                      style: const TextStyle(color: Color(0xFF059669), fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bouton "Télécharger rapport PDF" — MVP : SnackBar Premium
  Widget _buildBoutonRapport() {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: const Color(0xFF1E293B),
          content: Row(children: [
            const Text('🔒', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(_loc.t('stats_pdf_locked'),
                style: const TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w500))),
          ]),
          duration: const Duration(seconds: 3),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: _bleu.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
          color: context.appPrimaryLight,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.download_rounded, color: _bleu, size: 20),
            const SizedBox(width: 8),
            Text(_loc.t('stats_pdf_btn'),
                style: const TextStyle(color: _bleu, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: Text(_loc.t('stats_pdf_tag'),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309))),
            ),
          ],
        ),
      ),
    );
  }

  // ── Formatage nombre ──────────────────────────────────────────
  String _formatNombre(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}

// ── KPI Card (bandeau 2×2) ────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  const _KpiCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    // En mode sombre, on remplace le fond pastel par une teinte douce de la couleur principale
    final adaptedBg = Theme.of(context).brightness == Brightness.dark
        ? color.withValues(alpha: 0.18)
        : bgColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: adaptedBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1.1,
                    )),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Point de légende coloré
class _LegendeDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendeDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
    ],
  );
}

/// Placeholder photo miniature pour la carte meilleure annonce
class _MiniPhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 72, height: 72,
    color: context.appPrimaryLight,
    child: const Icon(Icons.home, size: 32, color: AppColors.primary),
  );
}

// ============================================================
// PROFIL PRESTATAIRE — Onglet dédié
// ============================================================
class ProfilPrestataireScreen extends StatefulWidget {
  final UserModel? user;
  const ProfilPrestataireScreen({super.key, this.user});

  @override
  State<ProfilPrestataireScreen> createState() => _ProfilPrestataireScreenState();
}

class _ProfilPrestataireScreenState extends State<ProfilPrestataireScreen> {
  late AppLocalizations _loc;
  UserModel? _user;

  bool _notifMessages = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadNotifPrefs();
  }

  Future<void> _loadNotifPrefs() async {
    final enabled = await NotificationService.isCategoryEnabled(
        NotificationService.kNotifMessages);
    if (!mounted) return;
    setState(() => _notifMessages = enabled);
  }

  Future<void> _toggleNotifMessages(bool value) async {
    setState(() => _notifMessages = value);
    await NotificationService.setCategory(NotificationService.kNotifMessages, value);
  }

  Future<void> _deconnecter() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_loc.t('profil_logout_confirm_title')),
        content: Text(_loc.t('profil_logout_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_loc.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(_loc.t('profil_logout_action')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final uid = AuthService.instance.currentUser?.id;
    if (uid != null) await NotificationService.clearToken(uid);
    await AuthService.instance.logout();
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionProfil(title: _loc.t('prest_section_info'), children: [
          if (u != null) ...[
            _InfoRowProfil(icon: Icons.person_outline, label: _loc.t('prest_info_name'),
                value: '${u.prenom} ${u.nom}'.trim()),
            if (u.telephone.isNotEmpty)
              _InfoRowProfil(icon: Icons.phone_outlined, label: _loc.t('prest_info_phone'), value: u.telephone),
          ],
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('prest_section_badges'), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (u?.isVerifie == true) _BadgeProfil(label: _loc.t('prest_badge_verified'), bg: AppColors.success),
              if (u?.isPremium == true) _BadgeProfil(label: _loc.t('prest_badge_premium'), bg: Colors.amber.shade600),
              _BadgeProfil(label: _loc.t('prest_badge_provider'), bg: AppColors.primary),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('prest_section_my_profile'), children: [
          ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
            ),
            title: Text(_loc.t('profil_edit')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => _FormulaireModificationProfil(user: u),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('profil_notifs'), children: [
          SwitchListTile(
            secondary: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 20),
            ),
            title: Text(_loc.t('prest_notif_messages'), style: AppTextStyles.bodyLarge),
            subtitle: Text(_loc.t('prest_notif_messages_sub'), style: const TextStyle(fontSize: 12)),
            value: _notifMessages,
            activeColor: AppColors.primary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onChanged: _toggleNotifMessages,
          ),
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('profil_info_section'), children: [
          ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.help_outline, color: AppColors.primary, size: 20),
            ),
            title: Text(_loc.t('profil_help')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AideFaqScreen())),
          ),
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('prest_section_support'), children: [
          _ContactOption(
            icon: Icons.support_agent_outlined,
            label: _loc.t('prest_support_name'),
            sublabel: _loc.t('prest_support_hours'),
            color: AppColors.primary,
            onTap: () async {
              final uri = Uri.parse('https://wa.me/237600000000');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
          ),
          const SizedBox(height: 8),
          _ContactOption(
            icon: Icons.mail_outline,
            label: _loc.t('prest_email_label'),
            sublabel: _loc.t('prest_email_sub'),
            color: Colors.teal,
            onTap: () async {
              final uri = Uri.parse('mailto:support@horemplus.app');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
          ),
        ]),
        const SizedBox(height: 12),
        _SectionProfil(title: _loc.t('prest_section_account'), children: [
          ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.logout, color: AppColors.error, size: 20),
            ),
            title: Text(_loc.t('profil_logout'),
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: _deconnecter,
          ),
        ]),
        const SizedBox(height: 12),
        Text(_loc.t('prest_version'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
      ],
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
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.88);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
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
      decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: AppColors.primary, size: 20),
    ),
    title: Text(label, style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
    subtitle: Text(value,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: context.appTextPrimary)),
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
          Text(sublabel, style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
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
  late AppLocalizations _loc;
  late final TextEditingController _prenomCtrl;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _telCtrl;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_loc.t('prest_profile_updated')),
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
          Text(_loc.t('profil_edit_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextFormField(
            controller: _prenomCtrl,
            decoration: InputDecoration(labelText: _loc.t('prest_edit_first_name'), prefixIcon: const Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nomCtrl,
            decoration: InputDecoration(labelText: _loc.t('prest_edit_last_name'), prefixIcon: const Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: _loc.t('prest_edit_phone'), prefixIcon: const Icon(Icons.phone_outlined),
                hintText: '+237 6XX XXX XXX'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _enregistrer,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_loc.t('common_save')),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ONGLET "MES PUBLICITÉS" — prestataire
// ============================================================
class _MesPublicitesTab extends StatefulWidget {
  final String uid;
  const _MesPublicitesTab({required this.uid});

  @override
  State<_MesPublicitesTab> createState() => _MesPublicitesTabState();
}

class _MesPublicitesTabState extends State<_MesPublicitesTab> {
  late AppLocalizations _loc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  Future<void> _ouvrirPublication() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PublierPubliciteScreen()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loc.t('pub_success')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmerSuppression(String pubId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_loc.t('pub_delete_title')),
        content: Text(_loc.t('pub_delete_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_loc.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(_loc.t('common_delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PubliciteService.supprimer(pubId);
    }
  }

  Future<void> _modifier(Publicite pub) async {
    final titreCtrl = TextEditingController(text: pub.titre);
    final descCtrl = TextEditingController(text: pub.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier la publicité'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titreCtrl,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_loc.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PubliciteService.mettreAJour(
        pub.id,
        titre: titreCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Publicité modifiée.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _reactiver(Publicite pub) async {
    final paye = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaiementPublicationScreen(
          logementId: pub.id,
          titreAnnonce: pub.titre,
          montant: PubliciteService.montantParPeriode,
          titreEcran: 'Réactiver la publicité',
          dureeLabel:
              'Nouvelle diffusion de ${PubliciteService.dureeJours} jours.',
          boutonLabel: 'Payer et réactiver',
          succesMessage:
              'Votre publicité est de nouveau en ligne pour ${PubliciteService.dureeJours} jours.',
          initierPersonnalise: ({required telephone, required operateur}) {
            return PaiementService.instance.initierPaiementPublicite(
              publiciteId: pub.id,
              telephone: telephone,
              channel: operateur,
            );
          },
        ),
      ),
    );
    if (paye == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Publicité réactivée.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirPublication,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.campaign_outlined),
        label: Text(_loc.t('pub_new_btn')),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: PubliciteService.getPublicitesPrestataire(widget.uid),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur : ${snap.error}',
                    style: const TextStyle(color: AppColors.error)),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: context.appPrimaryLight,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.campaign_outlined,
                          size: 48, color: AppColors.primary),
                    ),
                    const SizedBox(height: 20),
                    Text(_loc.t('pub_empty_title'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_loc.t('pub_empty_hint'),
                        style: TextStyle(color: context.appTextSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _ouvrirPublication,
                      icon: const Icon(Icons.add),
                      label: Text(_loc.t('pub_new_btn')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(200, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final pub = Publicite.fromMap(
                  docs[i].id, docs[i].data() as Map<String, dynamic>);
              return _CartePublicite(
                pub: pub,
                onSupprimer: () => _confirmerSuppression(pub.id),
                onModifier: () => _modifier(pub),
                onReactiver: () => _reactiver(pub),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Carte publicité dans le dashboard ────────────────────────
class _CartePublicite extends StatelessWidget {
  final Publicite pub;
  final VoidCallback onSupprimer;
  final VoidCallback onModifier;
  final VoidCallback onReactiver;

  const _CartePublicite({
    required this.pub,
    required this.onSupprimer,
    required this.onModifier,
    required this.onReactiver,
  });

  ({String label, Color color, IconData icon}) _statut() {
    if (pub.paymentPending) {
      return (
        label: 'En attente de paiement',
        color: Colors.orange,
        icon: Icons.hourglass_top
      );
    }
    if (pub.estExpiree) {
      return (
        label: 'Expirée — réactivez',
        color: AppColors.error,
        icon: Icons.timer_off
      );
    }
    if (pub.estDiffusable) {
      return (
        label: 'En diffusion',
        color: AppColors.success,
        icon: Icons.campaign
      );
    }
    return (
      label: 'Désactivée',
      color: AppColors.textHint,
      icon: Icons.pause_circle
    );
  }

  String _resteJusqua(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) return 'Échue';
    if (diff.inDays >= 1) return '${diff.inDays}j restants';
    if (diff.inHours >= 1) return '${diff.inHours}h restantes';
    return '< 1 h';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final st = _statut();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? context.appSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo de couverture + bandeau statut ──
          Stack(children: [
            if (pub.photos.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  pub.photos.first,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    color: context.appPrimaryLight,
                    child: const Icon(Icons.campaign_outlined,
                        color: AppColors.primary, size: 40),
                  ),
                ),
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: context.appPrimaryLight,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Center(
                  child: Icon(Icons.campaign_outlined,
                      color: AppColors.primary, size: 40),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: st.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(st.icon, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(st.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pub.titre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(pub.description,
                    style: TextStyle(
                        color: context.appTextSecondary, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),

                // ── Médias + échéance ──
                Row(
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 14, color: context.appTextHint),
                    const SizedBox(width: 4),
                    Text('${pub.photos.length} photo(s)',
                        style: TextStyle(
                            fontSize: 12, color: context.appTextHint)),
                    if (pub.videoUrl != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.videocam_outlined,
                          size: 14, color: context.appTextHint),
                      const SizedBox(width: 4),
                      Text('1 vidéo',
                          style: TextStyle(
                              fontSize: 12, color: context.appTextHint)),
                    ],
                    const Spacer(),
                    if (pub.expiresAt != null)
                      Text(_resteJusqua(pub.expiresAt!),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: pub.estExpiree
                                  ? AppColors.error
                                  : context.appTextSecondary)),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Actions ──
                Row(children: [
                  // Modifier : disponible tant que la pub n'est pas en attente paiement.
                  if (!pub.paymentPending) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onModifier,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Modifier'),
                        style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Réactiver : seulement si expirée.
                  if (pub.estExpiree && !pub.paymentPending) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onReactiver,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Réactiver'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Supprimer : toujours disponible.
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error),
                    onPressed: onSupprimer,
                    tooltip: l.t('common_delete'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}