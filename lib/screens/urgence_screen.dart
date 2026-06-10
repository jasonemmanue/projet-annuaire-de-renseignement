import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/paiement_service.dart';
import '../services/tarification_service.dart';
import '../widgets/operateur_selector.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/urgence_screen.dart
// Visiteur : paie un ACCÈS PRIORITAIRE 48 H sur une annonce.
// → débloque le contact du prestataire + message traité en priorité.
// Montant = grille URGENCES (selon grade + type), plancher 200 XAF.
// ============================================================

const int _kTimeoutSecondes = 120;

enum _Etape { formulaire, attente, succes, echec, timeout }

class UrgenceScreen extends StatefulWidget {
  final Logement logement;
  const UrgenceScreen({super.key, required this.logement});

  @override
  State<UrgenceScreen> createState() => _UrgenceScreenState();
}

class _UrgenceScreenState extends State<UrgenceScreen> {
  final _service = PaiementService.instance;
  late AppLocalizations _loc;

  _Etape _etape = _Etape.formulaire;
  bool _loading = false;
  String? _erreurForm;
  String? _reference;

  String? _operateur;
  String? _telephoneComplet;

  int _restant = _kTimeoutSecondes;
  Timer? _timer;
  Timer? _pollTimer;
  StreamSubscription<PaiementStatut>? _sub;

  late final int _montant;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    final grade = GradeBienLabel.fromCode(widget.logement.grade);
    _montant = TarificationService.instance
        .fraisUrgence(grade: grade, typeBien: widget.logement.typeBien);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  String _labelOperateur(String? op) =>
      op == 'mtn' ? 'MTN Mobile Money' : op == 'orange' ? 'Orange Money' : 'Mobile Money';

  Future<void> _payer() async {
    if (_operateur == null) {
      setState(() => _erreurForm = _loc.t('urgence_operator_hint'));
      return;
    }
    if (_telephoneComplet == null) {
      setState(() => _erreurForm = _loc.t('urgence_invalid_number'));
      return;
    }
    setState(() {
      _erreurForm = null;
      _loading = true;
    });

    final result = await _service.initierUrgence(
      logementId: widget.logement.id,
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
    if (result.checkoutUrl != null && result.checkoutUrl!.isNotEmpty) {
      try {
        await launchUrl(Uri.parse(result.checkoutUrl!),
            mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      _etape = _Etape.attente;
    });
    _demarrerAttente();
  }

  void _demarrerAttente() {
    _restant = _kTimeoutSecondes;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restant--);
      if (_restant <= 0) {
        t.cancel();
        _service.verifierPaiementServeur(_reference!).then((s) {
          if (!mounted) return;
          _terminer(s == PaiementStatut.reussi ? _Etape.succes : _Etape.timeout);
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
        title: Text(_loc.t('urgence_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: switch (_etape) {
          _Etape.formulaire => _buildFormulaire(),
          _Etape.attente => _buildAttente(),
          _Etape.succes => _buildSucces(),
          _Etape.echec => _buildEchec(
              _loc.t('urgence_payment_failed'),
              _loc.t('urgence_payment_failed_desc')),
          _Etape.timeout => _buildEchec(
              _loc.t('urgence_timeout'),
              _loc.t('urgence_timeout_desc')),
        },
      ),
    );
  }

  Widget _buildFormulaire() {
    final peut = _operateur != null && _telephoneComplet != null && !_loading;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _carteUrgence(),
        const SizedBox(height: 24),
        OperateurSelector(
          onChanged: (op, tel) => setState(() {
            _operateur = op;
            _telephoneComplet = tel;
          }),
        ),
        if (_erreurForm != null) ...[
          const SizedBox(height: 8),
          Text(_erreurForm!,
              style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: peut ? _payer : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text('${_loc.t('common_pay_prefix')} $_montant XAF via ${_labelOperateur(_operateur)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 13, color: AppColors.textHint),
          const SizedBox(width: 4),
          Text(_loc.t('urgence_secure_payment'),
              style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        ]),
      ],
    );
  }

  Widget _carteUrgence() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade700, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Text(_loc.t('urgence_badge'),
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.red.shade700)),
        ),
        const SizedBox(height: 14),
        Text(widget.logement.titre,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...[
          _loc.t('urgence_see_contact'),
          _loc.t('urgence_priority_msg'),
          _loc.t('urgence_access_duration'),
        ].map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ]),
            )),
        const Divider(color: Colors.white24, height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$_montant XAF',
              style: const TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(_loc.t('urgence_per_48h'),
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ]),
      ]),
    );
  }

  Widget _buildAttente() {
    final progress = _restant / _kTimeoutSecondes;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
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
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            '${_loc.t('urgence_validate_payment')} ${_labelOperateur(_operateur)} ${_loc.t('urgence_validate_on_phone')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: context.appTextSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _buildSucces() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration:
                const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 64),
          ),
          const SizedBox(height: 28),
          Text(_loc.t('urgence_success'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            _loc.t('urgence_success_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.appTextSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('urgence_see_contact_btn')),
          ),
        ]),
      ),
    );
  }

  Widget _buildEchec(String titre, String message) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.error_outline, color: AppColors.error, size: 56),
          ),
          const SizedBox(height: 24),
          Text(titre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: context.appTextSecondary)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _reessayer,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
