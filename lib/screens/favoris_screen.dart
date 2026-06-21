import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/favoris_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart' as sw;
import 'detail_logement_screen.dart';

// ============================================================
// FICHIER : lib/screens/favoris_screen.dart
// Écran Favoris — vrais favoris via FavorisService
// ✅ Firestore (connecté) | SharedPreferences (visiteur/offline)
// ✅ Loader pendant le chargement
// ✅ Suppression par swipe (Dismissible) + FavorisService
// ✅ Mode hors connexion avec bandeau + cache
// ✅ État vide avec illustration et CTA
// ============================================================

class FavorisScreen extends StatefulWidget {
  const FavorisScreen({super.key});

  @override
  State<FavorisScreen> createState() => _FavorisScreenState();
}

class _FavorisScreenState extends State<FavorisScreen> {
  final _service = FavorisService.instance;

  // Pour les visiteurs/offline : chargement ponctuel
  List<Logement>? _favoris;
  bool _horsConnexion = false;
  bool _chargement = false;
  String? _erreur;

  // Pour les utilisateurs connectés : Stream réactif Firestore
  Stream<List<Logement>>? _stream;
  // Abonnement au changement visiteur (IndexedStack reste monté)
  StreamSubscription<void>? _visiteurSub;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchFavoris();
    if (_stream == null) {
      // Visiteur / offline : chargement manuel + écoute des changements locaux
      _charger();
      _visiteurSub = FavorisService.onFavoriChanged.listen((_) {
        if (mounted) _charger(forceRefresh: true);
      });
    }
    _ecouterConnectivite();
  }

  @override
  void dispose() {
    _visiteurSub?.cancel();
    super.dispose();
  }

  // ─── Connectivité ─────────────────────────────────────────────────────────

  void _ecouterConnectivite() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      final horsConnexion = result == ConnectivityResult.none;
      if (horsConnexion != _horsConnexion) {
        setState(() => _horsConnexion = horsConnexion);
        if (!horsConnexion && _stream == null) {
          _charger(forceRefresh: true);
        }
      }
    });
  }

  // ─── Chargement ponctuel (visiteur / offline) ─────────────────────────────

  Future<void> _charger({bool forceRefresh = false}) async {
    if (_chargement) return;
    setState(() { _chargement = true; _erreur = null; });

    final result = await Connectivity().checkConnectivity();
    final horsConnexion = result == ConnectivityResult.none;

    try {
      final liste = await _service.getFavoris();
      if (!mounted) return;
      setState(() {
        _favoris = liste;
        _horsConnexion = horsConnexion;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les favoris.';
        _favoris = [];
        _chargement = false;
      });
    }
  }

  // ─── Suppression (swipe ou retrait) ───────────────────────────────────────

  Future<void> _supprimerFavori(Logement logement) async {
    final l = AppLocalizations.of(context);
    try {
      await _service.supprimerFavori(logement.id);
      // Si mode visiteur : mise à jour manuelle de la liste locale
      if (_stream == null && mounted) {
        setState(() => _favoris?.removeWhere((lo) => lo.id == logement.id));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.bookmark_remove, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(l.t('favoris_removed')),
          ]),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l.t('common_cancel'),
            onPressed: () async {
              await _service.ajouterFavori(logement);
              if (_stream == null) _charger(forceRefresh: true);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t('favoris_delete_error')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('favoris_title')),
        actions: [
          if (_stream == null && !_chargement)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.t('common_refresh'),
              onPressed: () => _charger(forceRefresh: true),
            ),
        ],
      ),
      body: Column(
        children: [
          _BandeauHorsConnexion(visible: _horsConnexion),
          if (_erreur != null)
            _BandeauErreur(message: _erreur!, onRetry: _charger),
          Expanded(child: _buildCorps()),
        ],
      ),
    );
  }

  Widget _buildCorps() {
    // Mode réactif : StreamBuilder pour utilisateurs connectés
    if (_stream != null) {
      return StreamBuilder<List<Logement>>(
        stream: _stream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoaderFavoris();
          }
          if (snap.hasError) {
            return Center(
              child: Text(AppLocalizations.of(context).t('favoris_load_error')),
            );
          }
          final liste = snap.data ?? [];
          if (liste.isEmpty) {
            return const _EtatVide();
          }
          return _buildListe(liste);
        },
      );
    }

    // Mode visiteur / offline : Future
    if (_chargement && _favoris == null) return const _LoaderFavoris();
    if (_chargement && _favoris != null) {
      return Stack(
        children: [
          _buildListe(_favoris!),
          const Positioned(
              top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
        ],
      );
    }
    if (_favoris == null || _favoris!.isEmpty) {
      return const _EtatVide();
    }
    return _buildListe(_favoris!);
  }

  Widget _buildListe(List<Logement> liste) {
    return RefreshIndicator(
      onRefresh: () => _charger(forceRefresh: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: liste.length,
        itemBuilder: (_, i) {
          final logement = liste[i];
          return Dismissible(
            key: ValueKey(logement.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              final l = AppLocalizations.of(context);
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l.t('favoris_confirm_remove')),
                      content: Text(
                          '"${logement.titre}"\n${l.t('favoris_confirm_remove_body')}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l.t('common_cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.error),
                          child: Text(l.t('favoris_remove_action')),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) => _supprimerFavori(logement),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, AppColors.error.withValues(alpha: 0.9)],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bookmark_remove, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).t('favoris_remove_action'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            child: sw.LogementCard(
              logement: logement,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DetailLogementScreen(logement: logement)),
                );
                // Stream met à jour automatiquement ; pour visiteur : refresh manuel
                if (_stream == null) _charger(forceRefresh: true);
              },
            ),
          );
        },
      ),
    );
  }
}

// ─── Widgets internes ─────────────────────────────────────────────────────────

class _BandeauHorsConnexion extends StatelessWidget {
  final bool visible;
  const _BandeauHorsConnexion({required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState:
      visible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.brown.shade50,
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 14, color: Colors.brown),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context).t('favoris_offline'),
                style: const TextStyle(fontSize: 12, color: Colors.brown),
              ),
            ),
          ],
        ),
      ),
      secondChild: const SizedBox.shrink(),
    );
  }
}

class _BandeauErreur extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _BandeauErreur({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.shade50,
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context).t('common_retry'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _LoaderFavoris extends StatelessWidget {
  const _LoaderFavoris();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 4,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

/// Skeleton shimmer pendant le chargement.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Image placeholder
          Container(
            width: 90,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, color: Colors.grey.shade200),
                const SizedBox(height: 8),
                Container(
                    height: 12,
                    width: 120,
                    color: Colors.grey.shade200),
                const SizedBox(height: 6),
                Container(
                    height: 12,
                    width: 80,
                    color: Colors.grey.shade200),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EtatVide extends StatelessWidget {
  const _EtatVide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 96,
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).t('favoris_empty'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).t('favoris_empty_sub'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}