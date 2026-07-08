import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../services/publicite_service.dart';
import '../theme/app_theme.dart';

// ============================================================
// FICHIER : lib/widgets/stories_publicites_overlay.dart
// Overlay plein écran style « Stories WhatsApp » pour diffuser
// les publicités actives aux visiteurs.
//
// Comportement :
//  • Photo  : auto-advance après 5 s
//  • Vidéo  : auto-advance à la fin de la lecture
//  • Tap gauche / droit  : pub précédente / suivante
//  • Bouton « Passer »   : ferme immédiatement
//  • Barre de progression segmentée en haut (1 segment par pub)
//
// Affichage déclenché côté MainNavigationScreen :
//  • Tous les 3 changements de tab
//  • Tous les 4 retours d'arrière-plan
// ============================================================

const int _kDureeImageMs = 5000;
const int _kMaxStories = 6;

/// Ouvre l'overlay si au moins une pub est disponible.
/// Retourne `true` si un overlay a été affiché.
Future<bool> ouvrirStoriesPublicites(BuildContext context) async {
  // Lit instantanément la liste pour décider rapidement.
  final stream = PubliciteService.watchPublicitesDiffusables();
  final pubs = await stream.first.timeout(
    const Duration(seconds: 3),
    onTimeout: () => <Publicite>[],
  );
  if (pubs.isEmpty) return false;

  // Sélection aléatoire de pubs (max 6) pour ne pas saturer l'utilisateur.
  final rnd = Random();
  final shuffled = List<Publicite>.from(pubs)..shuffle(rnd);
  final selection = shuffled.take(_kMaxStories).toList();

  if (!context.mounted) return false;
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          StoriesPublicitesOverlay(publicites: selection),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  return true;
}

class StoriesPublicitesOverlay extends StatefulWidget {
  final List<Publicite> publicites;
  const StoriesPublicitesOverlay({super.key, required this.publicites});

  @override
  State<StoriesPublicitesOverlay> createState() =>
      _StoriesPublicitesOverlayState();
}

class _StoriesPublicitesOverlayState extends State<StoriesPublicitesOverlay>
    with SingleTickerProviderStateMixin {
  late int _index;
  late AnimationController _progress;
  VideoPlayerController? _video;
  Timer? _photoTimer;

  @override
  void initState() {
    super.initState();
    _index = 0;
    _progress = AnimationController(vsync: this)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _suivant();
      });
    _afficherCourant();
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    _photoTimer?.cancel();
    super.dispose();
  }

  Publicite get _pub => widget.publicites[_index];

  bool get _aVideo =>
      _pub.videoUrl != null && _pub.videoUrl!.isNotEmpty;

  Future<void> _afficherCourant() async {
    // Reset
    _photoTimer?.cancel();
    await _video?.dispose();
    _video = null;
    _progress
      ..stop()
      ..reset();

    if (_aVideo) {
      try {
        _video = VideoPlayerController.networkUrl(Uri.parse(_pub.videoUrl!));
        await _video!.initialize();
        if (!mounted) return;
        final duree = _video!.value.duration;
        _progress.duration = duree.inMilliseconds > 0
            ? duree
            : const Duration(seconds: 8);
        _video!.play();
        _video!.addListener(_onVideoTick);
        _progress.forward();
        setState(() {});
      } catch (_) {
        // Vidéo invalide → bascule en mode photo
        _video = null;
        _modePhoto();
      }
    } else {
      _modePhoto();
    }
  }

  void _modePhoto() {
    _progress.duration = const Duration(milliseconds: _kDureeImageMs);
    _progress.forward();
    setState(() {});
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null) return;
    if (v.value.position >= v.value.duration &&
        v.value.duration > Duration.zero) {
      _suivant();
    }
  }

  void _suivant() {
    if (_index + 1 >= widget.publicites.length) {
      _fermer();
      return;
    }
    setState(() => _index++);
    _afficherCourant();
  }

  void _precedent() {
    if (_index <= 0) return;
    setState(() => _index--);
    _afficherCourant();
  }

  void _fermer() {
    if (mounted) Navigator.of(context).maybePop();
  }

  void _pause() {
    _progress.stop();
    _video?.pause();
  }

  void _reprendre() {
    _progress.forward();
    _video?.play();
  }

  @override
  Widget build(BuildContext context) {
    final pub = _pub;
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Contenu (vidéo / photo)
            Positioned.fill(child: _buildContenu(pub)),

            // Zones de tap gauche / droite
            Row(children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _precedent,
                  onLongPressStart: (_) => _pause(),
                  onLongPressEnd: (_) => _reprendre(),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _suivant,
                  onLongPressStart: (_) => _pause(),
                  onLongPressEnd: (_) => _reprendre(),
                ),
              ),
            ]),

            // Barre de progression segmentée
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.publicites.length, (i) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                          value: i < _index
                              ? 1.0
                              : i > _index
                                  ? 0.0
                                  : _progress.value,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // En-tête prestataire + bouton fermer
            Positioned(
              top: 30,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage: pub.prestatairePhoto != null &&
                            pub.prestatairePhoto!.isNotEmpty
                        ? NetworkImage(pub.prestatairePhoto!)
                        : null,
                    child: pub.prestatairePhoto == null ||
                            pub.prestatairePhoto!.isEmpty
                        ? const Icon(Icons.business,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pub.prestataireNom.isNotEmpty
                              ? pub.prestataireNom
                              : 'Prestataire',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'Sponsorisé',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fermer,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Bas : titre + description + bouton Passer
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pub.titre.isNotEmpty)
                    Container(
                      width: screenWidth,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pub.titre,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          if (pub.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              pub.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _suivant,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text(
                      'Passer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu(Publicite pub) {
    // Vidéo
    if (_video != null && _video!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: VideoPlayer(_video!),
        ),
      );
    }

    // Photo (première du tableau)
    final photo = pub.photos.isNotEmpty ? pub.photos.first : null;
    if (photo != null) {
      return Image.network(
        photo,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 64)),
      );
    }

    // Fallback : titre uniquement sur fond uni
    return Container(
      color: AppColors.primary.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: const Icon(Icons.campaign,
          color: Colors.white, size: 80),
    );
  }
}

// ============================================================
// COMPTEUR DÉCLENCHEUR — partagé entre la navigation et le cycle
// de vie de l'app.
//
//   • registerNavigation()    : appelé à chaque changement de tab
//   • registerForegroundReturn() : appelé sur AppLifecycleState.resumed
//
// Renvoie `true` si l'overlay doit être déclenché.
// ============================================================
class StoriesTrigger {
  StoriesTrigger._();
  static final StoriesTrigger instance = StoriesTrigger._();

  int _navCount = 0;
  int _resumeCount = 0;

  static const int _navSeuil = 3;
  static const int _resumeSeuil = 4;

  bool registerNavigation() {
    _navCount++;
    if (_navCount >= _navSeuil) {
      _navCount = 0;
      return true;
    }
    return false;
  }

  bool registerForegroundReturn() {
    _resumeCount++;
    if (_resumeCount >= _resumeSeuil) {
      _resumeCount = 0;
      return true;
    }
    return false;
  }
}
