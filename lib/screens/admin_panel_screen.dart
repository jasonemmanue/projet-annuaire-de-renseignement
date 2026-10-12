import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/admin_panel_screen.dart
// Panneau d'administration (accessible si role == 'admin').
// Onglets : Signalements · Annonces (file « À vérifier » = modération) ·
// Utilisateurs · Analytics.
//
// Données : API Horem+ (routes /admin, réservées au rôle admin).
//
// ── CRÉER UN ADMIN ──────────────────────────────────────────
// Ajouter son e-mail à la variable ADMIN_EMAILS du service
// horem-api sur Railway, puis se reconnecter : l'onglet Admin
// (bouclier) apparaît.
// ============================================================

final _api = ApiClient.instance;

/// Liste admin « temps réel » (relue toutes les 10 s, partagée).
Stream<List<Doc>> _fluxAdmin(String chemin, [Map<String, dynamic>? params]) =>
    _api.sonder(chemin, Doc.liste,
        intervalle: const Duration(seconds: 10),
        params: {'limit': 200, ...?params});

Future<void> _majAdmin(String chemin, Map<String, dynamic> champs) async {
  await _api.patch(chemin, champs);
  _api.rafraichir(chemin.substring(0, chemin.lastIndexOf('/')));
}

/// Modération d'une annonce : « valider » (visible des visiteurs) ou
/// « rejeter » (motif obligatoire). Le prestataire est prévenu par push.
Future<void> _moderer(BuildContext context, String logementId, String decision) async {
  final l = AppLocalizations.of(context);
  String? motif;
  if (decision == 'rejeter') {
    final ctrl = TextEditingController();
    motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('admin_reject_title')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: l.t('admin_reject_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l.t('admin_reject')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (motif == null || motif.isEmpty) return;
  }
  try {
    await _api.post('/admin/logements/$logementId/moderation',
        {'decision': decision, if (motif != null) 'motif': motif});
    _api.rafraichir('/admin/logements');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t(decision == 'valider' ? 'admin_validated' : 'admin_rejected'))));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.error));
    }
  }
}

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Row(children: [
            const Icon(Icons.shield, size: 20),
            const SizedBox(width: 8),
            Text(l.t('admin_title')),
          ]),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: const Icon(Icons.flag_outlined), text: l.t('admin_reports')),
              Tab(icon: const Icon(Icons.home_work_outlined), text: l.t('admin_listings')),
              Tab(icon: const Icon(Icons.people_outline), text: l.t('admin_users')),
              Tab(icon: const Icon(Icons.analytics_outlined), text: l.t('admin_analytics')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SignalementsTab(),
            _AnnoncesTab(),
            _UtilisateursTab(),
            _AnalyticsTab(),
          ],
        ),
      ),
    );
  }
}

class _SignalementsTab extends StatelessWidget {
  const _SignalementsTab();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stream = _fluxAdmin('/admin/signalements', {'statut': 'en_attente'});

    return StreamBuilder<List<Doc>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data ?? const <Doc>[];
        if (docs.isEmpty) {
          return _EmptyTab(
              icon: Icons.flag_outlined, text: l.t('admin_no_reports'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final s = SignalementModel.fromMap(docs[i].id, docs[i].data());
            return _SignalementCard(signalement: s);
          },
        );
      },
    );
  }
}

class _SignalementCard extends StatelessWidget {
  final SignalementModel signalement;
  const _SignalementCard({required this.signalement});

  Future<void> _traiter(BuildContext context) async {
    final l = AppLocalizations.of(context);
    await _majAdmin('/admin/signalements/${signalement.id}', {'statut': 'traite'});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('admin_report_treated'))),
      );
    }
  }

  Future<void> _supprimerAnnonce(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.t('admin_delete_listing_title')),
        content: Text(
            'L\'annonce « ${signalement.logementTitre} » et ses conversations seront supprimées définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l.t('common_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/admin/logements/${signalement.logementId}');
      await _majAdmin('/admin/signalements/${signalement.id}', {'statut': 'traite'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.t('admin_listing_deleted'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = signalement;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.flag, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.logementTitre,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 8),
          Text('${l.t('admin_report_reason')} ${s.motif}',
              style: const TextStyle(fontSize: 13)),
          if (s.motifLibre != null && s.motifLibre!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('« ${s.motifLibre} »',
                  style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 4),
          Text(
            '${l.t('admin_report_by')} ${s.signaleParType} · ${_fmtDate(s.dateSignalement)}',
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _traiter(context),
                icon: const Icon(Icons.check, size: 16),
                label: Text(l.t('admin_treat')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _supprimerAnnonce(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(l.t('common_delete')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// ONGLET 2 — ANNONCES
// ════════════════════════════════════════════════════════════
class _AnnoncesTab extends StatefulWidget {
  const _AnnoncesTab();
  @override
  State<_AnnoncesTab> createState() => _AnnoncesTabState();
}

class _AnnoncesTabState extends State<_AnnoncesTab> {
  final _searchCtrl = TextEditingController();
  String _filtre = 'AVerifier'; // AVerifier | Toutes | Sponsorisées | Signalées  (clés internes)
  Set<String> _signaledIds = {};

  @override
  void initState() {
    super.initState();
    // Charge les IDs d'annonces signalées (en attente) pour le filtre.
    _fluxAdmin('/admin/signalements', {'statut': 'en_attente'}).listen((docs) {
      if (!mounted) return;
      setState(() {
        _signaledIds = docs
            .map((d) => (d.data()['logementId'] as String?) ?? '')
            .where((e) => e.isNotEmpty)
            .toSet();
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filterLabels = {
      'AVerifier': l.t('admin_filter_to_review'),
      'Toutes': l.t('admin_filter_all'),
      'Sponsorisées': l.t('admin_filter_sponsored'),
      'Signalées': l.t('admin_filter_reported'),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.t('admin_search'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: ['AVerifier', 'Toutes', 'Sponsorisées', 'Signalées'].map((f) {
              final sel = _filtre == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filterLabels[f]!),
                  selected: sel,
                  onSelected: (_) => setState(() => _filtre = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Doc>>(
            // File de modération filtrée par le serveur (toute la base).
            stream: _filtre == 'AVerifier'
                ? _fluxAdmin('/admin/logements', {'filtre': 'a_verifier'})
                : _fluxAdmin('/admin/logements'),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data ?? const <Doc>[];
              final q = _searchCtrl.text.trim().toLowerCase();

              var liste = docs.where((d) {
                final data = d.data();
                final titre = (data['titre'] ?? '').toString().toLowerCase();
                final ville = (data['ville'] ?? '').toString().toLowerCase();
                if (q.isNotEmpty &&
                    !titre.contains(q) &&
                    !ville.contains(q)) {
                  return false;
                }
                if (_filtre == 'Sponsorisées') {
                  return data['isSponsored'] == true;
                }
                if (_filtre == 'Signalées') {
                  return _signaledIds.contains(d.id);
                }
                return true;
              }).toList();

              if (liste.isEmpty) {
                return _EmptyTab(
                    icon: _filtre == 'AVerifier' ? Icons.verified_outlined : Icons.home_work_outlined,
                    text: l.t(_filtre == 'AVerifier' ? 'admin_no_to_review' : 'admin_no_listings'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _AdminAnnonceCard(
                  doc: liste[i],
                  signalee: _signaledIds.contains(liste[i].id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AdminAnnonceCard extends StatelessWidget {
  final Doc doc;
  final bool signalee;
  const _AdminAnnonceCard({required this.doc, required this.signalee});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = doc.data();
    final titre = data['titre'] ?? 'Sans titre';
    final ville = data['ville'] ?? '';
    final photos = List<String>.from(data['photos'] ?? []);
    // « Suspendre » = retirer l'autorisation admin (visibleAdmin).
    final isVisible = data['visibleAdmin'] != false;
    final isSponsored = data['isSponsored'] == true;
    final statut = (data['statutModeration'] ?? 'valide') as String;
    final estVerifie = data['estVerifie'] == true;
    final chemin = '/admin/logements/${doc.id}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isVisible ? AppColors.border : AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: photos.isNotEmpty
                ? Image.network(photos.first,
                    width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (ctx, _, __) => _ph(ctx))
                : _ph(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(ville,
                    style: TextStyle(
                        color: context.appTextSecondary, fontSize: 12)),
                if (statut == 'en_attente') ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _moderer(context, doc.id, 'valider'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact),
                        child: Text(l.t('admin_validate')),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _moderer(context, doc.id, 'rejeter'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            visualDensity: VisualDensity.compact),
                        child: Text(l.t('admin_reject')),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (statut == 'en_attente') _tag(l.t('moderation_pending'), AppColors.warning),
                  if (statut == 'rejete') _tag(l.t('moderation_rejected'), AppColors.error),
                  if (estVerifie) _tag(l.t('detail_verified'), AppColors.primary),
                  if (isSponsored) _tag(l.t('admin_tag_sponsored'), AppColors.success),
                  if (signalee) _tag(l.t('admin_tag_reported'), AppColors.error),
                  if (!isVisible) _tag(l.t('admin_suspended'), AppColors.textHint),
                ]),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'valider' || v == 'rejeter') {
                await _moderer(context, doc.id, v);
              } else if (v == 'verifier') {
                await _majAdmin(chemin, {'estVerifie': !estVerifie});
              } else if (v == 'suspendre') {
                await _majAdmin(chemin, {'visibleAdmin': false});
              } else if (v == 'reactiver') {
                await _majAdmin(chemin, {'visibleAdmin': true});
              } else if (v == 'supprimer') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(l.t('admin_delete_title')),
                    content: Text('Supprimer définitivement « $titre » ?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l.t('common_cancel'))),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error),
                          child: Text(l.t('common_delete'))),
                    ],
                  ),
                );
                if (ok == true) {
                  await _api.delete(chemin);
                  _api.rafraichir('/admin/logements');
                }
              }
            },
            itemBuilder: (_) => [
              if (statut != 'valide')
                PopupMenuItem(value: 'valider', child: Text(l.t('admin_validate'))),
              if (statut != 'rejete')
                PopupMenuItem(value: 'rejeter', child: Text(l.t('admin_reject'))),
              PopupMenuItem(
                  value: 'verifier',
                  child: Text(l.t(estVerifie ? 'admin_unverify' : 'admin_verify'))),
              if (isVisible)
                PopupMenuItem(value: 'suspendre', child: Text(l.t('admin_suspend')))
              else
                PopupMenuItem(value: 'reactiver', child: Text(l.t('admin_reactivate'))),
              PopupMenuItem(value: 'supprimer', child: Text(l.t('common_delete'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ph(BuildContext context) => Container(
      width: 56, height: 56, color: context.appPrimaryLight,
      child: const Icon(Icons.home, color: AppColors.primary));

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6)),
        child: Text(t,
            style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

// ════════════════════════════════════════════════════════════
// ONGLET 3 — UTILISATEURS
// ════════════════════════════════════════════════════════════
class _UtilisateursTab extends StatefulWidget {
  const _UtilisateursTab();
  @override
  State<_UtilisateursTab> createState() => _UtilisateursTabState();
}

class _UtilisateursTabState extends State<_UtilisateursTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ouvrirCreerCompteGratuit() async {
    final l = AppLocalizations.of(context);
    final nomCtrl = TextEditingController();
    final prenomCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final telCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.t('admin_creer_gratuit_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: prenomCtrl,
                decoration: InputDecoration(labelText: l.t('admin_creer_gratuit_prenom')),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nomCtrl,
                decoration: InputDecoration(labelText: l.t('admin_creer_gratuit_nom')),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                decoration: InputDecoration(labelText: l.t('admin_creer_gratuit_email')),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                decoration: InputDecoration(labelText: l.t('admin_creer_gratuit_password')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: telCtrl,
                decoration: InputDecoration(labelText: l.t('admin_creer_gratuit_tel')),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: Text(l.t('admin_creer_gratuit_btn')),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final nom = nomCtrl.text.trim();
    final prenom = prenomCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;
    String tel = telCtrl.text.trim();
    if (nom.isEmpty || prenom.isEmpty || email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t('admin_creer_gratuit_champs_requis')),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    if (tel.isNotEmpty && !tel.startsWith('+')) tel = '+237$tel';

    try {
      await _api.post('/admin/comptes-gratuits', {
        'email': email,
        'password': password,
        'nom': nom,
        'prenom': prenom,
        'telephone': tel,
      });
      _api.rafraichir('/admin/users');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t('admin_creer_gratuit_ok')),
        backgroundColor: AppColors.success,
      ));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${l.t('admin_creer_gratuit_error')} (${e.statusCode}) ${e.message}'),
          backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${l.t('admin_creer_gratuit_error')}: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.t('admin_search_users'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _ouvrirCreerCompteGratuit,
              icon: const Icon(Icons.card_giftcard, size: 16),
              label: Text(l.t('admin_creer_gratuit_btn')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Doc>>(
            stream: _fluxAdmin('/admin/users', {'role': 'prestataire'}),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data ?? const <Doc>[];
              final q = _searchCtrl.text.trim().toLowerCase();
              final liste = docs.where((d) {
                if (q.isEmpty) return true;
                final data = d.data();
                final nom =
                    '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'.toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                return nom.contains(q) || email.contains(q);
              }).toList();

              if (liste.isEmpty) {
                return _EmptyTab(
                    icon: Icons.people_outline,
                    text: l.t('admin_no_users'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _AdminUserCard(doc: liste[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AdminUserCard extends StatelessWidget {
  final Doc doc;
  const _AdminUserCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = doc.data();
    final nom = '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'.trim();
    final email = data['email'] ?? '';
    final tel = data['telephone'] ?? '';
    final isPremium = data['isPremium'] == true;
    final isVerifie = data['isVerifie'] == true;
    // Un compte suspendu est refusé par l'API.
    final isSuspended = data['suspendu'] == true;
    final isGratuit = data['compteGratuit'] == true;
    final chemin = '/admin/users/${doc.id}';
    Future<void> maj(Map<String, dynamic> champs) => _majAdmin(chemin, champs);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: context.appPrimaryLight,
              child: Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nom.isEmpty ? l.t('admin_anonymous') : nom,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(email,
                      style: TextStyle(
                          color: context.appTextSecondary, fontSize: 12)),
                  if (tel.toString().isNotEmpty)
                    Text(tel,
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 11)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            if (isVerifie) _tag(l.t('admin_tag_verified'), AppColors.success),
            if (isPremium) _tag(l.t('admin_tag_premium'), Colors.amber.shade800),
            if (isSuspended) _tag(l.t('admin_tag_suspended_user'), AppColors.error),
            if (isGratuit) _tag(l.t('admin_tag_compte_gratuit'), AppColors.success),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (!isVerifie)
              _miniBtn(l.t('admin_verify_btn'), Icons.verified_outlined,
                  () => maj({'isVerifie': true})),
            if (!isPremium)
              _miniBtn(l.t('admin_activate_premium'), Icons.workspace_premium, () {
                final expiry =
                    DateTime.now().add(const Duration(days: 30));
                maj({
                  'isPremium': true,
                  'premiumExpiry': apiDateTexte(expiry),
                });
              }),
            isGratuit
                ? _miniBtn(l.t('admin_gratuit_off_btn'), Icons.card_giftcard,
                    () => maj({'compteGratuit': false}))
                : _miniBtn(l.t('admin_gratuit_on_btn'), Icons.card_giftcard,
                    () => maj({'compteGratuit': true})),
            isSuspended
                ? _miniBtn(l.t('admin_activate_btn'), Icons.lock_open,
                    () => maj({'suspendu': false}))
                : _miniBtn(l.t('admin_suspend_btn'), Icons.block,
                    () => maj({'suspendu': true})),
          ]),
        ],
      ),
    );
  }

  Widget _miniBtn(String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(0, 32)),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6)),
        child: Text(t,
            style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

// ════════════════════════════════════════════════════════════
// ONGLET 4 — ANALYTICS
// ════════════════════════════════════════════════════════════
class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab();
  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _charger();
  }

  Future<Map<String, dynamic>> _charger() async {
    // Comptages faits par le serveur (requêtes SQL agrégées).
    final st = await _api.get('/admin/stats') as Map<String, dynamic>;
    final last = ApiClient.items(
        await _api.get('/admin/transactions', params: {'limit': 5}));
    return {
      'annonces': st['totalAnnonces'] ?? 0,
      'prestataires': st['prestataires'] ?? 0,
      'msgToday': st['conversationsAujourdhui'] ?? 0,
      'signalements': st['signalementsEnAttente'] ?? 0,
      'revenus': (st['revenusMois'] as num? ?? 0).toDouble(),
      'last': last,
    };
  }

  Future<void> _refresh() async {
    setState(() => _future = _charger());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        final last = (d['last'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _kpi('🏠', l.t('admin_kpi_listings'), '${d['annonces']}'),
                  _kpi('👤', l.t('admin_kpi_providers'), '${d['prestataires']}'),
                  _kpi('💬', l.t('admin_kpi_messages'), '${d['msgToday']}'),
                  _kpi('🚩', l.t('admin_kpi_reports'), '${d['signalements']}'),
                ],
              ),
              const SizedBox(height: 12),
              _kpiLarge('💰', l.t('admin_revenue_month'),
                  '${(d['revenus'] as double).toStringAsFixed(0)} XAF'),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _dialogNotifGlobale(context),
                icon: const Icon(Icons.campaign),
                label: Text(l.t('admin_global_notif')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46)),
              ),
              const SizedBox(height: 20),
              Text(l.t('admin_last_tx'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              if (last.isEmpty)
                Text(l.t('admin_no_tx'),
                    style: const TextStyle(color: AppColors.textHint))
              else
                ...last.map((t) => ListTile(
                      dense: true,
                      leading: Icon(
                        t['type'] == 'premium'
                            ? Icons.workspace_premium
                            : Icons.rocket_launch,
                        color: AppColors.primary,
                      ),
                      title: Text(
                          '${t['type'] ?? '?'} · ${(t['montant'] as num? ?? 0)} XAF'),
                      subtitle: Text(t['uid']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _statutChip(t['statut']?.toString() ?? ''),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _kpi(String emoji, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: context.appPrimaryLight,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: context.appTextSecondary)),
          ],
        ),
      );

  Widget _kpiLarge(String emoji, String label, String value) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      );

  Widget _statutChip(String statut) {
    Color c = AppColors.textHint;
    if (statut == 'reussi') c = AppColors.success;
    if (statut == 'echoue') c = AppColors.error;
    return Text(statut, style: TextStyle(color: c, fontSize: 11));
  }

  void _dialogNotifGlobale(BuildContext context) {
    final l = AppLocalizations.of(context);
    final titreCtrl = TextEditingController();
    final corpsCtrl = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(l.t('admin_notif_dialog_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titreCtrl,
                decoration: InputDecoration(labelText: l.t('admin_notif_title_field')),
              ),
              TextField(
                controller: corpsCtrl,
                decoration: InputDecoration(labelText: l.t('admin_notif_msg_field')),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.t('common_cancel'))),
            ElevatedButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (titreCtrl.text.trim().isEmpty ||
                          corpsCtrl.text.trim().isEmpty) {
                        return;
                      }
                      setSt(() => sending = true);
                      final ok = await _envoyerNotifGlobale(
                          titreCtrl.text.trim(), corpsCtrl.text.trim());
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? l.t('admin_notif_sent')
                            : l.t('admin_notif_failed')),
                        backgroundColor:
                            ok ? AppColors.success : AppColors.error,
                      ));
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.t('common_send')),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _envoyerNotifGlobale(String titre, String corps) async {
    try {
      final data = await _api.post('/admin/notification-globale',
          {'titre': titre, 'corps': corps}) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

// ── Helpers communs ──────────────────────────────────────────
class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyTab({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: context.appTextSecondary)),
          ],
        ),
      );
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
