import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/activation_email_service.dart';
import '../services/auth_service.dart';
import '../services/paiement_service.dart';
import '../widgets/operateur_selector.dart';
import '../widgets/silent_payment_webview.dart';
import '../widgets/shared_widgets.dart' as sw;
import '../l10n/app_localizations.dart';
import 'ios_activation_email_screen.dart';

// ============================================================
// FICHIER : lib/screens/urgence_screen.dart
// Visiteur : alerte prioritaire — notifié en premier quand un
// bien correspondant est publié. 200 XAF / 48 H.
// ============================================================

const int _kMontantAlerte = 200;
const int _kTimeoutSecondes = 120;

const _typeAutre = 'Autre';

const _typeBienOptions = <String>[
  'Studio',
  'Appartement',
  'Villa',
  'Terrain',
  'Bureau',
  'Commerce',
  'Chambre',
  _typeAutre,
];

// ── Page principale : liste des alertes ─────────────────────────

class UrgenceScreen extends StatefulWidget {
  const UrgenceScreen({super.key});

  @override
  State<UrgenceScreen> createState() => _UrgenceScreenState();
}

class _UrgenceScreenState extends State<UrgenceScreen> {
  late AppLocalizations _loc;
  final _db = FirebaseFirestore.instance;

  String? get _uid => AuthService.instance.currentUser?.id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  Stream<List<AlerteUrgence>> _watchAlertes() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('urgences')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AlerteUrgence.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> _supprimerAlerte(AlerteUrgence alerte) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_loc.t('urgence_delete_confirm')),
        content: Text(_loc.t('urgence_delete_confirm_body')),
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
    if (confirm != true) return;
    await _db.collection('urgences').doc(alerte.id).delete();
  }

  void _ouvrirFormulaire({AlerteUrgence? existante}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FormulaireAlerteScreen(alerte: existante),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loc.t('urgence_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: sw.SkylineBackground(
        child: StreamBuilder<List<AlerteUrgence>>(
          stream: _watchAlertes(),
          builder: (context, snap) {
            final alertes = snap.data ?? [];
            return CustomScrollView(
              slivers: [
                // ── Question en haut ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade700, Colors.red.shade400],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(_loc.t('urgence_badge'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: Colors.red.shade700)),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _loc.t('urgence_question'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          ...[
                            _loc.t('urgence_benefit_1'),
                            _loc.t('urgence_benefit_2'),
                            _loc.t('urgence_benefit_3'),
                          ].map((t) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(t,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13)),
                                  ),
                                ]),
                              )),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _ouvrirFormulaire(),
                              icon: const Icon(Icons.add_alert, size: 20),
                              label: Text(_loc.t('urgence_new_alert')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red.shade700,
                                minimumSize: const Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Titre "Mes alertes" ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(_loc.t('urgence_my_alerts'),
                        style: AppTextStyles.h3
                            .copyWith(color: Colors.white)),
                  ),
                ),
                // ── Liste ou vide ──
                if (alertes.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          _loc.t('urgence_no_alerts'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _AlerteCard(
                        alerte: alertes[i],
                        loc: _loc,
                        onRenew: () =>
                            _ouvrirFormulaire(existante: alertes[i]),
                        onDelete: () => _supprimerAlerte(alertes[i]),
                      ),
                      childCount: alertes.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Card d'une alerte ──────────────────────────────────────────

class _AlerteCard extends StatelessWidget {
  final AlerteUrgence alerte;
  final AppLocalizations loc;
  final VoidCallback onRenew;
  final VoidCallback onDelete;

  const _AlerteCard({
    required this.alerte,
    required this.loc,
    required this.onRenew,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = alerte.estActive;
    final isExpired = alerte.estExpiree;
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.92);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.success.withValues(alpha: 0.5)
              : isExpired
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.accent.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                  color: isActive ? AppColors.success : AppColors.textHint,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alerte.typeBien,
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                _StatusBadge(
                  label: isActive
                      ? loc.t('urgence_active_until')
                      : isExpired
                          ? loc.t('urgence_expired')
                          : loc.t('urgence_pending'),
                  color: isActive
                      ? AppColors.success
                      : isExpired
                          ? AppColors.error
                          : AppColors.accent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alerte.description,
                style: AppTextStyles.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.monetization_on_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                '${NumberFormat('#,###', 'fr').format(alerte.prixMin)} — ${NumberFormat('#,###', 'fr').format(alerte.prixMax)} XAF',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
            ]),
            if (isActive && alerte.expiresAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${loc.t('urgence_active_until')} ${DateFormat('dd/MM/yyyy HH:mm').format(alerte.expiresAt!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.success),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              if (isExpired || (!isActive && !alerte.paymentPending))
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRenew,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(loc.t('urgence_renew'),
                        style: const TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (isExpired || (!isActive && !alerte.paymentPending))
                const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.error,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// FORMULAIRE ALERTE + PAIEMENT
// ════════════════════════════════════════════════════════════════

enum _Etape { formulaire, attente, succes, echec, timeout }

class _FormulaireAlerteScreen extends StatefulWidget {
  final AlerteUrgence? alerte;
  const _FormulaireAlerteScreen({this.alerte});

  @override
  State<_FormulaireAlerteScreen> createState() =>
      _FormulaireAlerteScreenState();
}

class _FormulaireAlerteScreenState extends State<_FormulaireAlerteScreen> {
  final _service = PaiementService.instance;
  final _db = FirebaseFirestore.instance;
  late AppLocalizations _loc;

  _Etape _etape = _Etape.formulaire;
  bool _loading = false;
  String? _erreurForm;
  String? _reference;
  String? _checkoutUrl;
  bool _fallbackLance = false;

  String? _operateur;
  String? _telephoneComplet;

  int _restant = _kTimeoutSecondes;
  Timer? _timer;
  Timer? _pollTimer;
  StreamSubscription<PaiementStatut>? _sub;

  // Champs formulaire
  String _typeBien = 'Studio';
  final _typeBienAutreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prixMinCtrl = TextEditingController();
  final _prixMaxCtrl = TextEditingController();

  bool get _isAutre => _typeBien == _typeAutre;
  String get _typeBienEffectif =>
      _isAutre && _typeBienAutreCtrl.text.trim().isNotEmpty
          ? _typeBienAutreCtrl.text.trim()
          : _typeBien;

  String? _alerteDocId;

  @override
  void initState() {
    super.initState();
    if (widget.alerte != null) {
      if (_typeBienOptions.contains(widget.alerte!.typeBien)) {
        _typeBien = widget.alerte!.typeBien;
      } else {
        _typeBien = _typeAutre;
        _typeBienAutreCtrl.text = widget.alerte!.typeBien;
      }
      _descCtrl.text = widget.alerte!.description;
      _prixMinCtrl.text = widget.alerte!.prixMin.toStringAsFixed(0);
      _prixMaxCtrl.text = widget.alerte!.prixMax.toStringAsFixed(0);
      _alerteDocId = widget.alerte!.id;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    _sub?.cancel();
    _typeBienAutreCtrl.dispose();
    _descCtrl.dispose();
    _prixMinCtrl.dispose();
    _prixMaxCtrl.dispose();
    super.dispose();
  }

  String _labelOperateur(String? op) => op == 'mtn'
      ? 'MTN Mobile Money'
      : op == 'orange'
          ? 'Orange Money'
          : 'Mobile Money';

  Future<void> _validerEtPayer() async {
    if (_isAutre && _typeBienAutreCtrl.text.trim().isEmpty) {
      setState(() => _erreurForm = _loc.t('urgence_type_error'));
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      setState(() => _erreurForm = _loc.t('urgence_desc_error'));
      return;
    }
    final pMin = double.tryParse(_prixMinCtrl.text.replaceAll(' ', '')) ?? 0;
    final pMax = double.tryParse(_prixMaxCtrl.text.replaceAll(' ', '')) ?? 0;
    if (pMax > 0 && pMax < pMin) {
      setState(() => _erreurForm = _loc.t('urgence_prix_error'));
      return;
    }
    // iOS : opérateur/téléphone sont saisis sur la page web de paiement.
    if (!isExternalActivationRequired) {
      if (_operateur == null) {
        setState(() => _erreurForm = _loc.t('urgence_operator_hint'));
        return;
      }
      if (_telephoneComplet == null) {
        setState(() => _erreurForm = _loc.t('urgence_invalid_number'));
        return;
      }
    }
    setState(() {
      _erreurForm = null;
      _loading = true;
    });

    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _erreurForm = 'Non connecté';
      });
      return;
    }

    // Créer ou mettre à jour le document alerte
    final docRef = _alerteDocId != null
        ? _db.collection('urgences').doc(_alerteDocId)
        : _db.collection('urgences').doc();
    _alerteDocId = docRef.id;

    await docRef.set({
      'uid': uid,
      'typeBien': _typeBienEffectif,
      'description': _descCtrl.text.trim(),
      'prixMin': pMin,
      'prixMax': pMax,
      'actif': false,
      'paymentPending': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // iOS : bascule vers activation par email (App Store 3.1.1)
    if (isExternalActivationRequired) {
      if (!mounted) return;
      setState(() => _loading = false);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => IosActivationEmailScreen(
            type: ActivationType.urgence,
            serviceLabel: 'Alerte prioritaire (48 h)',
            targetId: _alerteDocId,
          ),
        ),
      );
      return;
    }

    // Initier le paiement
    final result = await _service.initierUrgence(
      logementId: _alerteDocId!,
      telephone: _telephoneComplet!,
      operateur: _operateur,
    );
    if (!mounted) return;
    if (!result.success || result.reference == null) {
      setState(() {
        _loading = false;
        _erreurForm = result.message;
      });
      return;
    }
    _reference = result.reference;
    _checkoutUrl = result.checkoutUrl;
    setState(() {
      _loading = false;
      _etape = _Etape.attente;
    });
    _demarrerAttente();
  }

  void _demarrerAttente() {
    _restant = _kTimeoutSecondes;
    _fallbackLance = false;
    HapticFeedback.lightImpact();
    _sub = _service.watchStatut(_reference!).listen((s) {
      if (!mounted) return;
      if (s == PaiementStatut.reussi) _terminer(_Etape.succes);
      else if (s == PaiementStatut.echoue) _terminer(_Etape.echec);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final s = await _service.verifierPaiementServeur(_reference!);
      if (!mounted) return;
      if (s == PaiementStatut.reussi) _terminer(_Etape.succes);
      else if (s == PaiementStatut.echoue) _terminer(_Etape.echec);
    });
    Timer(const Duration(seconds: 15), () async {
      if (!mounted || _etape != _Etape.attente || _fallbackLance) return;
      _fallbackLance = true;
      final s = await _service.verifierPaiementServeur(_reference!);
      if (!mounted || _etape != _Etape.attente) return;
      if (s == PaiementStatut.enAttente &&
          _checkoutUrl != null &&
          _checkoutUrl!.isNotEmpty) {
        try {
          await launchUrl(Uri.parse(_checkoutUrl!),
              mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restant--);
      if (_restant <= 0) {
        t.cancel();
        _service.verifierPaiementServeur(_reference!).then((s) {
          if (!mounted) return;
          _terminer(
              s == PaiementStatut.reussi ? _Etape.succes : _Etape.timeout);
        });
      }
    });
  }

  void _terminer(_Etape e) {
    _timer?.cancel();
    _pollTimer?.cancel();
    _sub?.cancel();
    if (!mounted) return;
    setState(() => _etape = e);
  }

  void _reessayer() {
    _timer?.cancel();
    _pollTimer?.cancel();
    _sub?.cancel();
    setState(() {
      _etape = _Etape.formulaire;
      _reference = null;
      _restant = _kTimeoutSecondes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.alerte != null
            ? _loc.t('urgence_renew')
            : _loc.t('urgence_new_alert')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: sw.SkylineBackground(
          child: Stack(
            children: [
              if (_checkoutUrl != null &&
                  _checkoutUrl!.isNotEmpty &&
                  _etape == _Etape.attente)
                Positioned(
                  top: 0,
                  left: 0,
                  child: SilentPaymentWebView(url: _checkoutUrl!),
                ),
              switch (_etape) {
                _Etape.formulaire => _buildFormulaire(),
                _Etape.attente => _buildAttente(),
                _Etape.succes => _buildSucces(),
                _Etape.echec => _buildEchec(
                    _loc.t('urgence_payment_failed'),
                    _loc.t('urgence_payment_failed_desc')),
                _Etape.timeout => _buildEchec(
                    _loc.t('urgence_timeout'), _loc.t('urgence_timeout_desc')),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormulaire() {
    final peut =
        _operateur != null && _telephoneComplet != null && !_loading;
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.88);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type de bien
              Text(_loc.t('urgence_type_bien'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _typeBien,
                items: _typeBienOptions
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _typeBien = v);
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_isAutre) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _typeBienAutreCtrl,
                  decoration: InputDecoration(
                    hintText: _loc.t('urgence_type_autre_hint'),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Description
              Text(_loc.t('urgence_description'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: _loc.t('urgence_description_hint'),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              // Fourchette de prix
              Text(_loc.t('urgence_prix_range'), style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _prixMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _loc.t('urgence_prix_min'),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prixMaxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _loc.t('urgence_prix_max'),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              // Opérateur + numéro — masqué sur iOS (paiement via page web).
              if (!isExternalActivationRequired)
                OperateurSelector(
                  onChanged: (op, tel) => setState(() {
                    _operateur = op;
                    _telephoneComplet = tel;
                  }),
                ),
              if (_erreurForm != null) ...[
                const SizedBox(height: 8),
                Text(_erreurForm!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: peut ? _validerEtPayer : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        isExternalActivationRequired
                            ? _loc.t('ios_activation_send_button')
                            : widget.alerte != null
                                ? '${_loc.t('common_pay_prefix')} $_kMontantAlerte XAF via ${_labelOperateur(_operateur)}'
                                : _loc.t('urgence_submit'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(_loc.t('urgence_secure_payment'),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                  ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttente() {
    final progress = _restant / _kTimeoutSecondes;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 40),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: context.appPrimaryLight,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              Text('${_restant}s',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ]),
          ),
          const SizedBox(height: 28),
          Text(_loc.t('urgence_sent'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            '${_loc.t('urgence_validate_payment')} ${_labelOperateur(_operateur)} ${_loc.t('urgence_validate_on_phone')}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: context.appTextSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _buildSucces() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 64),
          ),
          const SizedBox(height: 28),
          Text(_loc.t('urgence_success'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            _loc.t('urgence_success_desc'),
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: context.appTextSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('urgence_return')),
          ),
        ]),
      ),
    );
  }

  Widget _buildEchec(String titre, String message) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.error_outline,
                color: AppColors.error, size: 56),
          ),
          const SizedBox(height: 24),
          Text(titre,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: context.appTextSecondary)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _reessayer,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('common_retry')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_loc.t('common_cancel')),
          ),
        ]),
      ),
    );
  }
}
