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

  List<Logement>? _favoris;      // null = en cours de chargement
  bool _horsConnexion = false;
  bool _chargement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
    _ecouterConnectivite();
  }

  // ─── Connectivité ─────────────────────────────────────────────────────────

  void _ecouterConnectivite() {
    Connectivity().onConnectivityChanged.listen((result) {
      final horsConnexion = result == ConnectivityResult.none;
      if (horsConnexion != _horsConnexion) {
        setState(() => _horsConnexion = horsConnexion);
        if (!horsConnexion) {
          // Retour en ligne : rechargement depuis Firestore
          _charger(forceRefresh: true);
        }
      }
    });
  }

  // ─── Chargement ───────────────────────────────────────────────────────────

  Future<void> _charger({bool forceRefresh = false}) async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    // Vérification connectivité initiale
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

  // ─── Suppression ──────────────────────────────────────────────────────────

  Future<void> _supprimerFavori(int index, Logement logement) async {
    // Suppression optimiste de l'UI
    setState(() => _favoris!.removeAt(index));
    final l = AppLocalizations.of(context);

    try {
      await _service.supprimerFavori(logement.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.t('favoris_removed')),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l.t('common_cancel'),
            onPressed: () async {
              await _service.ajouterFavori(logement);
              await _charger(forceRefresh: true);
            },
          ),
        ),
      );
    } catch (e) {
      // Rollback si erreur
      if (!mounted) return;
      setState(() => _favoris!.insert(index, logement));
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
        title: Text(
          _favoris == null || _favoris!.isEmpty
              ? l.t('favoris_title')
              : '${l.t('favoris_title')} (${_favoris!.length})',
        ),
        actions: [
          if (!_chargement)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.t('common_refresh'),
              onPressed: () => _charger(forceRefresh: true),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Bandeau hors connexion ─────────────────────────────────────
          _BandeauHorsConnexion(visible: _horsConnexion),

          // ── Bandeau erreur ─────────────────────────────────────────────
          if (_erreur != null)
            _BandeauErreur(
              message: _erreur!,
              onRetry: _charger,
            ),

          // ── Corps ─────────────────────────────────────────────────────
          Expanded(child: _buildCorps()),
        ],
      ),
    );
  }

  Widget _buildCorps() {
    // Chargement initial
    if (_chargement && _favoris == null) {
      return const _LoaderFavoris();
    }

    // Chargement rafraîchissement (liste déjà affichée)
    if (_chargement && _favoris != null) {
      return Stack(
        children: [
          _buildListe(_favoris!),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
        ],
      );
    }

    // État vide
    if (_favoris == null || _favoris!.isEmpty) {
      return _EtatVide(onExplorer: () => Navigator.pop(context));
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
                builder: (_) => AlertDialog(
                  title: Text(l.t('favoris_confirm_remove')),
                  content: Text('Retirer "${logement.titre}" de vos favoris ?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l.t('common_cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        l.t('favoris_remove_action'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ) ??
                  false;
            },
            onDismissed: (_) => _supprimerFavori(
              liste.indexOf(logement),
              logement,
            ),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: AppColors.error,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite_border, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).t('favoris_remove_action'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
                    builder: (_) => DetailLogementScreen(logement: logement),
                  ),
                );
                // Rafraîchissement au retour (l'utilisateur a pu toggler le favori)
                _charger(forceRefresh: true);
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
  final VoidCallback onExplorer;
  const _EtatVide({required this.onExplorer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.favorite_border,
              size: 72,
              color: Colors.grey,
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onExplorer,
              icon: const Icon(Icons.search),
              label: Text(AppLocalizations.of(context).t('favoris_explore')),
            ),
          ],
        ),
      ),
    );
  }
}