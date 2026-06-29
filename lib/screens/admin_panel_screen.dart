import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/logement_service.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/admin_panel_screen.dart
// Panneau d'administration (accessible si role == 'admin').
// Onglets : Signalements · Annonces · Utilisateurs · Analytics.
//
// ── CRÉER LE PREMIER ADMIN ──────────────────────────────────
// 1. Créez un compte prestataire normal depuis l'app.
// 2. Dans la console Firebase → Firestore → users/{uid},
//    modifiez le champ "role" de "prestataire" en "admin".
// 3. Reconnectez-vous : l'onglet Admin (bouclier) apparaît.
// ============================================================

const String _kFunctionsBase =
    'https://us-central1-sgk-home.cloudfunctions.net';

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
    final stream = FirebaseFirestore.instance
        .collection('signalements')
        .where('statut', isEqualTo: 'en_attente')
        .orderBy('dateSignalement', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _EmptyTab(
              icon: Icons.flag_outlined, text: l.t('admin_no_reports'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final s = SignalementModel.fromMap(
                docs[i].id, docs[i].data() as Map<String, dynamic>);
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
    await FirebaseFirestore.instance
        .collection('signalements')
        .doc(signalement.id)
        .update({'statut': 'traite'});
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
      await LogementService.deleteLogement(signalement.logementId);
      await FirebaseFirestore.instance
          .collection('signalements')
          .doc(signalement.id)
          .update({'statut': 'traite'});
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
  String _filtre = 'Toutes'; // Toutes | Sponsorisées | Signalées  (clés internes)
  Set<String> _signaledIds = {};

  @override
  void initState() {
    super.initState();
    // Charge les IDs d'annonces signalées (en attente) pour le filtre.
    FirebaseFirestore.instance
        .collection('signalements')
        .where('statut', isEqualTo: 'en_attente')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _signaledIds = snap.docs
            .map((d) => (d.data()['logementId'] as String?) ?? '')
            .where((e) => e.isNotEmpty)
            .toSet();
      });
    });
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
            children: ['Toutes', 'Sponsorisées', 'Signalées'].map((f) {
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
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('logements')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data?.docs ?? [];
              final q = _searchCtrl.text.trim().toLowerCase();

              var liste = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
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
                    icon: Icons.home_work_outlined,
                    text: l.t('admin_no_listings'));
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
  final QueryDocumentSnapshot doc;
  final bool signalee;
  const _AdminAnnonceCard({required this.doc, required this.signalee});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>;
    final titre = data['titre'] ?? 'Sans titre';
    final ville = data['ville'] ?? '';
    final photos = List<String>.from(data['photos'] ?? []);
    final isVisible = data['isVisible'] != false; // défaut visible
    final isSponsored = data['isSponsored'] == true;
    final ref = doc.reference;

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
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  if (isSponsored) _tag(l.t('admin_tag_sponsored'), AppColors.success),
                  if (signalee) _tag(l.t('admin_tag_reported'), AppColors.error),
                  if (!isVisible) _tag(l.t('admin_suspended'), AppColors.textHint),
                ]),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'suspendre') {
                await ref.update({'isVisible': false});
              } else if (v == 'reactiver') {
                await ref.update({'isVisible': true});
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
                if (ok == true) await LogementService.deleteLogement(doc.id);
              }
            },
            itemBuilder: (_) => [
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'prestataire')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data?.docs ?? [];
              final q = _searchCtrl.text.trim().toLowerCase();
              final liste = docs.where((d) {
                if (q.isEmpty) return true;
                final data = d.data() as Map<String, dynamic>;
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
  final QueryDocumentSnapshot doc;
  const _AdminUserCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>;
    final nom = '${data['prenom'] ?? ''} ${data['nom'] ?? ''}'.trim();
    final email = data['email'] ?? '';
    final tel = data['telephone'] ?? '';
    final isPremium = data['isPremium'] == true;
    final isVerifie = data['isVerifie'] == true;
    final isSuspended = data['isSuspended'] == true;
    final ref = doc.reference;

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
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (!isVerifie)
              _miniBtn(l.t('admin_verify_btn'), Icons.verified_outlined,
                  () => ref.update({'isVerifie': true})),
            if (!isPremium)
              _miniBtn(l.t('admin_activate_premium'), Icons.workspace_premium, () {
                final expiry =
                    DateTime.now().add(const Duration(days: 30));
                ref.update({
                  'isPremium': true,
                  'premiumExpiry': Timestamp.fromDate(expiry),
                });
              }),
            isSuspended
                ? _miniBtn(l.t('admin_activate_btn'), Icons.lock_open,
                    () => ref.update({'isSuspended': false}))
                : _miniBtn(l.t('admin_suspend_btn'), Icons.block,
                    () => ref.update({'isSuspended': true})),
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
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final debutJour = DateTime(now.year, now.month, now.day);
    final debutMois = DateTime(now.year, now.month, 1);

    final annonces = await db.collection('logements').count().get();
    final prestataires = await db
        .collection('users')
        .where('role', isEqualTo: 'prestataire')
        .count()
        .get();
    final msgToday = await db
        .collection('conversations')
        .where('lastMessageTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(debutJour))
        .count()
        .get();
    final signalements = await db
        .collection('signalements')
        .where('statut', isEqualTo: 'en_attente')
        .count()
        .get();

    // Revenus du mois (transactions réussies)
    final txReussies =
        await db.collection('transactions').where('statut', isEqualTo: 'reussi').get();
    double revenus = 0;
    for (final d in txReussies.docs) {
      final data = d.data();
      final created = (data['createdAt'] as Timestamp?)?.toDate();
      if (created != null && created.isAfter(debutMois)) {
        revenus += (data['montant'] as num? ?? 0).toDouble();
      }
    }

    // 5 dernières transactions
    final last = await db
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .get();

    return {
      'annonces': annonces.count ?? 0,
      'prestataires': prestataires.count ?? 0,
      'msgToday': msgToday.count ?? 0,
      'signalements': signalements.count ?? 0,
      'revenus': revenus,
      'last': last.docs.map((d) => d.data()).toList(),
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final token = await user.getIdToken();
      final res = await http.post(
        Uri.parse('$_kFunctionsBase/envoyerNotifGlobale'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'titre': titre, 'corps': corps}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return res.statusCode == 200 && data['success'] == true;
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
