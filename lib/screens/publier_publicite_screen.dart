import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../l10n/app_localizations.dart';
import '../utils/media_permission.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/publicite_service.dart';
import '../services/paiement_service.dart';
import 'paiement_publication_screen.dart';

// ============================================================
// ÉCRAN : PublierPubliciteScreen
// Permet au prestataire de publier une publicité photo/vidéo
// pour promouvoir son activité sur l'accueil visiteur.
// La publicité doit être liée à une annonce existante.
// ============================================================

class PublierPubliciteScreen extends StatefulWidget {
  const PublierPubliciteScreen({super.key});

  @override
  State<PublierPubliciteScreen> createState() =>
      _PublierPubliciteScreenState();
}

class _PublierPubliciteScreenState extends State<PublierPubliciteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final List<XFile> _photos = [];
  XFile? _video;
  VideoPlayerController? _videoController;

  bool _isSubmitting = false;

  // Annonce liée
  List<Logement> _mesAnnonces = [];
  bool _loadingAnnonces = true;
  Logement? _annonceSelectionnee;

  static const int _maxPhotos = 5;

  @override
  void initState() {
    super.initState();
    _chargerMesAnnonces();
  }

  Future<void> _chargerMesAnnonces() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingAnnonces = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('logements')
          .where('uid_prestataire', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();
      if (!mounted) return;
      setState(() {
        _mesAnnonces = snap.docs
            .map((d) => Logement.fromMap(d.id, d.data()))
            .toList();
        _loadingAnnonces = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAnnonces = false);
    }
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descCtrl.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ── Sélection annonce liée ────────────────────────────────────

  void _choisirAnnonce(AppLocalizations l) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(l.t('pub_select_listing_hint'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _mesAnnonces.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = _mesAnnonces[i];
                  final isSelected = _annonceSelectionnee?.id == a.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: a.photos.isNotEmpty
                          ? Image.network(a.photos.first,
                              width: 50, height: 50, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 50, height: 50,
                                color: context.appPrimaryLight,
                                child: const Icon(Icons.home, color: AppColors.primary, size: 24),
                              ))
                          : Container(
                              width: 50, height: 50,
                              color: context.appPrimaryLight,
                              child: const Icon(Icons.home, color: AppColors.primary, size: 24),
                            ),
                    ),
                    title: Text(a.titre,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${a.typeBien} — ${a.quartier}, ${a.ville}',
                      style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.primary)
                        : const Icon(Icons.radio_button_off, color: AppColors.textHint),
                    onTap: () {
                      setState(() => _annonceSelectionnee = a);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sélection médias ─────────────────────────────────────────

  Future<void> _choisirPhotos() async {
    if (_photos.length >= _maxPhotos) return;
    if (!await demanderPermissionMedia(context, MediaType.photos)) return;
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      imageQuality: 80,
      limit: _maxPhotos - _photos.length,
    );
    if (images.isNotEmpty) setState(() => _photos.addAll(images));
  }

  Future<void> _prendrePhoto() async {
    if (_photos.length >= _maxPhotos) return;
    if (!await demanderPermissionMedia(context, MediaType.camera)) return;
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (img != null) setState(() => _photos.add(img));
  }

  Future<void> _choisirVideo() async {
    if (!await demanderPermissionMedia(context, MediaType.videos)) return;
    final picker = ImagePicker();
    final vid = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (vid == null) return;
    final ctrl = VideoPlayerController.file(File(vid.path));
    await ctrl.initialize();
    _videoController?.dispose();
    setState(() {
      _video = vid;
      _videoController = ctrl;
    });
  }

  // ── Publication ───────────────────────────────────────────────

  Future<void> _publier() async {
    if (!_formKey.currentState!.validate()) return;
    if (_annonceSelectionnee == null) {
      _showSnack(AppLocalizations.of(context).t('pub_listing_required'));
      return;
    }
    if (_photos.isEmpty) {
      _showSnack(AppLocalizations.of(context).t('pub_error_no_photo'));
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      _showSnack('Session expirée — reconnectez-vous');
      return;
    }
    await firebaseUser.getIdToken(true);

    setState(() => _isSubmitting = true);
    try {
      final user = AuthService.instance.currentUser!;
      final annonce = _annonceSelectionnee!;

      final pubId = await PubliciteService.creerBrouillon(
        prestataireId: user.id,
        prestataireNom: '${user.prenom} ${user.nom}'.trim(),
        prestatairePhone: user.telephone,
        prestatairePhoto: user.photoUrl,
        titre: _titreCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        photos: _photos,
        video: _video,
        logementId: annonce.id,
        logementTitre: annonce.titre,
        logementPhoto: annonce.photos.isNotEmpty ? annonce.photos.first : null,
      );

      if (!mounted) return;

      // Compte gratuit → bypass paiement publicité
      if (AuthService.instance.currentUser?.compteGratuit == true) {
        final until = DateTime.now()
            .add(const Duration(days: PubliciteService.dureeJours));
        await FirebaseFirestore.instance
            .collection('publicites')
            .doc(pubId)
            .update({
          'actif': true,
          'paymentPending': false,
          'expiresAt': Timestamp.fromDate(until),
        });
        if (mounted) {
          _showSnack(AppLocalizations.of(context).t('pub_success'));
          Navigator.pop(context, true);
        }
        return;
      }

      // Étape 2 : paiement 500 XAF / 4 jours via Mobile Money.
      final paye = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaiementPublicationScreen(
            logementId: pubId,
            titreAnnonce: _titreCtrl.text.trim(),
            montant: PubliciteService.montantParPeriode,
            titreEcran: 'Paiement publicité',
            dureeLabel:
                'Diffusion pendant ${PubliciteService.dureeJours} jours. La pub sera automatiquement désactivée à l\'échéance.',
            boutonLabel: 'Payer et diffuser',
            succesMessage:
                'Votre publicité est en ligne pour ${PubliciteService.dureeJours} jours.',
            initierPersonnalise: ({required telephone, required operateur}) {
              return PaiementService.instance.initierPaiementPublicite(
                publiciteId: pubId,
                telephone: telephone,
                channel: operateur,
              );
            },
          ),
        ),
      );

      if (paye == true) {
        if (mounted) {
          _showSnack(AppLocalizations.of(context).t('pub_success'));
          Navigator.pop(context, true);
        }
      } else {
        // Paiement annulé/échoué → on supprime le brouillon.
        try {
          await PubliciteService.supprimer(pubId);
        } catch (_) {}
        if (mounted) {
          _showSnack('Publicité annulée : aucun paiement validé.');
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final detail = msg.contains('permission') || msg.contains('unauthorized')
            ? 'Permissions Firebase insuffisantes. Vérifie les Rules Storage et Firestore.'
            : msg.contains('network') || msg.contains('socket')
                ? 'Erreur réseau — vérifie ta connexion.'
                : msg;
        _showSnack('Erreur : $detail');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('pub_new_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isSubmitting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 20),
                  Text(l.t('pub_uploading'), style: AppTextStyles.bodyMedium),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Sélection de l'annonce liée ────────────
                  Text(l.t('pub_select_listing'), style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  if (_loadingAnnonces)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else if (_mesAnnonces.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l.t('pub_no_listings_available'),
                              style: const TextStyle(fontSize: 13, color: AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _choisirAnnonce(l),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color ?? context.appSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _annonceSelectionnee != null
                                ? AppColors.primary
                                : AppColors.textHint.withValues(alpha: 0.3),
                          ),
                        ),
                        child: _annonceSelectionnee != null
                            ? Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _annonceSelectionnee!.photos.isNotEmpty
                                        ? Image.network(
                                            _annonceSelectionnee!.photos.first,
                                            width: 56, height: 56, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 56, height: 56,
                                              color: context.appPrimaryLight,
                                              child: const Icon(Icons.home, color: AppColors.primary),
                                            ),
                                          )
                                        : Container(
                                            width: 56, height: 56,
                                            color: context.appPrimaryLight,
                                            child: const Icon(Icons.home, color: AppColors.primary),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _annonceSelectionnee!.titre,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_annonceSelectionnee!.typeBien} — ${_annonceSelectionnee!.quartier}, ${_annonceSelectionnee!.ville}',
                                          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                                ],
                              )
                            : Row(
                                children: [
                                  Container(
                                    width: 56, height: 56,
                                    decoration: BoxDecoration(
                                      color: context.appPrimaryLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.add_home_outlined, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      l.t('pub_select_listing_hint'),
                                      style: TextStyle(fontSize: 13, color: context.appTextSecondary),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textHint),
                                ],
                              ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── Titre ──────────────────────────────────
                  Text(l.t('pub_field_title'), style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titreCtrl,
                    decoration:
                        InputDecoration(hintText: l.t('pub_field_title_hint')),
                    maxLength: 80,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.t('form_required')
                        : null,
                  ),

                  const SizedBox(height: 16),

                  // ── Description ────────────────────────────
                  Text(l.t('pub_field_desc'), style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descCtrl,
                    decoration:
                        InputDecoration(hintText: l.t('pub_field_desc_hint')),
                    maxLines: 4,
                    maxLength: 500,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.t('form_required')
                        : null,
                  ),

                  const SizedBox(height: 20),

                  // ── Photos ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l.t('pub_photos')} (${_photos.length}/$_maxPhotos)',
                        style: AppTextStyles.h3,
                      ),
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.photo_library_outlined,
                              color: AppColors.primary),
                          onPressed: _choisirPhotos,
                          tooltip: l.t('pub_pick_gallery'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt_outlined,
                              color: AppColors.primary),
                          onPressed: _prendrePhoto,
                          tooltip: l.t('pub_pick_camera'),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_photos.isEmpty)
                    _MediaSlotVide(
                      icon: Icons.add_photo_alternate_outlined,
                      label: l.t('pub_photos_hint'),
                      onTap: _choisirPhotos,
                    )
                  else
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length +
                            (_photos.length < _maxPhotos ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          if (i == _photos.length) {
                            return _MediaSlotVide(
                              icon: Icons.add_photo_alternate_outlined,
                              label: '+',
                              onTap: _choisirPhotos,
                              largeur: 90,
                            );
                          }
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_photos[i].path),
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _photos.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ── Vidéo (optionnelle) ────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l.t('pub_video')} (${l.t('pub_video_optional')})',
                        style: AppTextStyles.h3,
                      ),
                      IconButton(
                        icon: const Icon(Icons.video_library_outlined,
                            color: AppColors.primary),
                        onPressed: _choisirVideo,
                        tooltip: l.t('pub_pick_video'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_videoController != null &&
                      _videoController!.value.isInitialized)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _videoController!.value.isPlaying
                                ? _videoController!.pause()
                                : _videoController!.play();
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              _videoController!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () {
                              _videoController?.dispose();
                              setState(() {
                                _video = null;
                                _videoController = null;
                              });
                            },
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    _MediaSlotVide(
                      icon: Icons.videocam_outlined,
                      label: l.t('pub_video_hint'),
                      onTap: _choisirVideo,
                    ),

                  const SizedBox(height: 32),

                  // ── Bouton publier ─────────────────────────
                  ElevatedButton.icon(
                    onPressed: _publier,
                    icon: const Icon(Icons.campaign_outlined),
                    label: Text(l.t('pub_submit')),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

// ── Slot média vide cliquable ─────────────────────────────────
class _MediaSlotVide extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double largeur;

  const _MediaSlotVide({
    required this.icon,
    required this.label,
    required this.onTap,
    this.largeur = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: largeur == double.infinity ? null : largeur,
        height: 120,
        decoration: BoxDecoration(
          color: context.appPrimaryLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: AppColors.primary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
