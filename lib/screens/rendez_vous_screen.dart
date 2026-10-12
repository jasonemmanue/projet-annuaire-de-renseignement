// ============================================================
// FICHIER : lib/screens/rendez_vous_screen.dart
//
// Rendez-vous de visite (API /rendez-vous) :
//   • demanderVisite() : depuis le détail d'une annonce, le chercheur
//     choisit une date et une heure (+ message) ;
//   • RendezVousScreen : liste « Mes demandes » (chercheur) et, pour un
//     prestataire, « Visites reçues » avec Accepter / Refuser.
// Le demandeur peut annuler. Chaque action prévient l'autre partie (push).
// ============================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

final _api = ApiClient.instance;

/// Identifiant de l'appelant tel que l'API le voit (compte ou visiteur).
Future<String> _monId() async {
  final u = FirebaseAuth.instance.currentUser;
  if (u != null && !u.isAnonymous) return u.uid;
  return _api.visiteurId();
}

/// Feuille « Planifier une visite » depuis le détail d'une annonce.
Future<void> demanderVisite(BuildContext context, Logement logement) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FormulaireVisite(logement: logement),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).t('rdv_sent')),
      backgroundColor: AppColors.success,
    ));
  }
}

class _FormulaireVisite extends StatefulWidget {
  final Logement logement;
  const _FormulaireVisite({required this.logement});

  @override
  State<_FormulaireVisite> createState() => _FormulaireVisiteState();
}

class _FormulaireVisiteState extends State<_FormulaireVisite> {
  DateTime? _date;
  TimeOfDay? _heure;
  final _message = TextEditingController();
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  bool get _sansCompte {
    final u = FirebaseAuth.instance.currentUser;
    return u == null || u.isAnonymous;
  }

  @override
  void dispose() {
    _message.dispose();
    _nom.dispose();
    _tel.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _choisirHeure() async {
    final h = await showTimePicker(
      context: context,
      initialTime: _heure ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (h != null) setState(() => _heure = h);
  }

  DateTime? get _quand => (_date == null || _heure == null)
      ? null
      : DateTime(_date!.year, _date!.month, _date!.day, _heure!.hour, _heure!.minute);

  Future<void> _envoyer() async {
    final l = AppLocalizations.of(context);
    final quand = _quand;
    if (quand == null) {
      setState(() => _erreur = l.t('rdv_pick_datetime'));
      return;
    }
    if (_sansCompte && _tel.text.trim().isEmpty) {
      setState(() => _erreur = l.t('rdv_phone_required'));
      return;
    }
    setState(() { _envoi = true; _erreur = null; });
    try {
      await _api.post('/rendez-vous', {
        'logementId': widget.logement.id,
        'dateHeure': apiDateTexte(quand),
        'message': _message.text.trim(),
        if (_nom.text.trim().isNotEmpty) 'nom': _nom.text.trim(),
        if (_tel.text.trim().isNotEmpty) 'telephone': _tel.text.trim(),
      });
      _api.rafraichir('/rendez-vous');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _envoi = false; _erreur = e.message; });
    } catch (_) {
      setState(() { _envoi = false; _erreur = l.t('rdv_error'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loc = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text(l.t('rdv_title'), style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(widget.logement.titre, style: TextStyle(color: context.appTextSecondary)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _choisirDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(_date == null ? l.t('rdv_date') : DateFormat.yMMMd(loc).format(_date!)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _choisirHeure,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_heure == null ? l.t('rdv_time') : _heure!.format(context)),
              ),
            ),
          ]),
          if (_sansCompte) ...[
            const SizedBox(height: 12),
            TextField(controller: _nom,
                decoration: InputDecoration(labelText: l.t('rdv_name'), prefixIcon: const Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: _tel, keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.t('rdv_phone'), prefixIcon: const Icon(Icons.phone_outlined))),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 3,
            decoration: InputDecoration(labelText: l.t('rdv_message'), hintText: l.t('rdv_message_hint')),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 10),
            Text(_erreur!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _envoi ? null : _envoyer,
            icon: _envoi
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(l.t('rdv_send')),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ]),
      ),
    );
  }
}

/// Liste des rendez-vous de l'utilisateur. `prestataire` ajoute l'onglet
/// « Visites reçues ».
class RendezVousScreen extends StatelessWidget {
  final bool prestataire;
  const RendezVousScreen({super.key, this.prestataire = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: _monId(),
      builder: (context, idSnap) {
        final monId = idSnap.data;
        return DefaultTabController(
          length: prestataire ? 2 : 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.t('rdv_list_title')),
              bottom: prestataire
                  ? TabBar(tabs: [Tab(text: l.t('rdv_tab_received')), Tab(text: l.t('rdv_tab_mine'))])
                  : null,
            ),
            body: monId == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Doc>>(
                    stream: _api.sonder('/rendez-vous', Doc.liste,
                        intervalle: const Duration(seconds: 15)),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return snap.hasError
                            ? Center(child: Text(l.t('rdv_error')))
                            : const Center(child: CircularProgressIndicator());
                      }
                      final recus = snap.data!.where((d) => d['prestataireId'] == monId).toList();
                      final miens = snap.data!.where((d) => d['demandeurId'] == monId).toList();
                      final vues = prestataire
                          ? [_Liste(docs: recus, recus: true), _Liste(docs: miens, recus: false)]
                          : [_Liste(docs: miens, recus: false)];
                      return prestataire ? TabBarView(children: vues) : vues.first;
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _Liste extends StatelessWidget {
  final List<Doc> docs;
  final bool recus;
  const _Liste({required this.docs, required this.recus});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_available_outlined, size: 56, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(l.t(recus ? 'rdv_empty_received' : 'rdv_empty_mine'),
                textAlign: TextAlign.center, style: TextStyle(color: context.appTextSecondary)),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CarteRdv(doc: docs[i], recu: recus),
    );
  }
}

class _CarteRdv extends StatelessWidget {
  final Doc doc;
  final bool recu;
  const _CarteRdv({required this.doc, required this.recu});

  Future<void> _maj(BuildContext context, String statut, {bool demanderMotif = false}) async {
    final l = AppLocalizations.of(context);
    String? reponse;
    if (demanderMotif) {
      final ctrl = TextEditingController();
      reponse = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.t('rdv_refuse_title')),
          content: TextField(controller: ctrl, maxLines: 2,
              decoration: InputDecoration(hintText: l.t('rdv_refuse_hint'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('common_cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(l.t('rdv_refuse'))),
          ],
        ),
      );
      ctrl.dispose();
      if (reponse == null) return;
    }
    try {
      await _api.patch('/rendez-vous/${doc.id}', {'statut': statut, if (reponse != null) 'reponse': reponse});
      _api.rafraichir('/rendez-vous');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = doc.data();
    final quand = apiDate(d['dateHeure']);
    final statut = (d['statut'] ?? 'en_attente') as String;
    final couleur = switch (statut) {
      'accepte' => AppColors.success,
      'refuse' => AppColors.error,
      'annule' => AppColors.textHint,
      _ => AppColors.primary,
    };
    final loc = Localizations.localeOf(context).languageCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event, color: couleur, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(quand == null ? '—' : DateFormat.yMMMMEEEEd(loc).add_Hm().format(quand),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(l.t('rdv_status_$statut'),
                style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(d['logementTitre'] ?? '', style: TextStyle(color: context.appTextSecondary)),
        if (recu) ...[
          const SizedBox(height: 4),
          Text('${d['demandeurNom'] ?? ''}${(d['demandeurTelephone'] ?? '').toString().isNotEmpty ? ' · ${d['demandeurTelephone']}' : ''}',
              style: const TextStyle(fontSize: 13)),
        ],
        if ((d['message'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('« ${d['message']} »', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
        ],
        if ((d['reponse'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${l.t('rdv_reply')} ${d['reponse']}', style: const TextStyle(fontSize: 13)),
        ],
        if (recu && statut == 'en_attente') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _maj(context, 'accepte'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                child: Text(l.t('rdv_accept')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _maj(context, 'refuse', demanderMotif: true),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: Text(l.t('rdv_refuse')),
              ),
            ),
          ]),
        ],
        if (!recu && (statut == 'en_attente' || statut == 'accepte')) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _maj(context, 'annule'), child: Text(l.t('rdv_cancel'))),
          ),
        ],
      ]),
    );
  }
}
