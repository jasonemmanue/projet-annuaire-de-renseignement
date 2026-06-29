import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/paiement_service.dart';
import '../widgets/operateur_selector.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/sponsorisation_screen.dart
// Sponsorisation d'une annonce via Mobile Money (self-service).
// 1 sem = 7 500 XAF · 2 sem = 12 000 XAF · 1 mois = 20 000 XAF.
// ============================================================

const int _kTimeoutSecondes = 120;

class _Offre {
  final String code; // '1s' | '2s' | '1m'
  final String titre;
  final int montant;
  final String? badge;
  const _Offre(this.code, this.titre, this.montant, [this.badge]);
}

const List<_Offre> _offres = [
  _Offre('1s', '1 semaine', 7500, 'Recommandé'),
  _Offre('2s', '2 semaines', 12000),
  _Offre('1m', '1 mois', 20000, 'Meilleure valeur'),
];

enum _Etape { formulaire, attente, succes, echec, timeout }

class SponsorisationScreen extends StatefulWidget {
  final String logementId;
  final String titre;
  final String? photo;

  const SponsorisationScreen({
    super.key,
    required this.logementId,
    required this.titre,
    this.photo,
  });

  @override
  State<SponsorisationScreen> createState() => _SponsorisationScreenState();
}

class _SponsorisationScreenState extends State<SponsorisationScreen> {
  final _service = PaiementService.instance;
  late AppLocalizations _loc;

  _Etape _etape = _Etape.formulaire;
  String _dureeCode = '1s';
  bool _loading = false;
  String? _erreurForm;
  String? _reference;
  String? _operateur;
  String? _telephoneComplet;
  String? _telephoneInitial;

  int _restant = _kTimeoutSecondes;
  Timer? _timer;
  StreamSubscription<PaiementStatut>? _sub;

  int get _montant =>
      _offres.firstWhere((o) => o.code == _dureeCode).montant;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loc = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    final tel = AuthService.instance.currentUser?.telephone ?? '';
    if (tel.isNotEmpty) _telephoneInitial = tel;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  String _labelOperateur(String? op) =>
      op == 'mtn' ? 'MTN MoMo' : op == 'orange' ? 'Orange Money' : 'Mobile Money';

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

    final result = await _service.initierSponsorisation(
      logementId: widget.logementId,
      telephone: _telephoneComplet!,
      channel: _operateur,
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
    // PawaPay Cameroun : USSD push — pas de redirect externe.
    setState(() {
      _loading = false;
      _etape = _Etape.attente;
    });
    _demarrerAttente();
  }

  void _demarrerAttente() {
    _restant = _kTimeoutSecondes;
    HapticFeedback.lightImpact();
    _sub = _service.watchStatut(_reference!).listen((statut) {
      if (!mounted) return;
      if (statut == PaiementStatut.reussi) {
        _terminer(_Etape.succes);
      } else if (statut == PaiementStatut.echoue) {
        _terminer(_Etape.echec);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restant--);
      if (_restant <= 0) {
        t.cancel();
        _service.verifierStatut(_reference!).then((s) {
          if (!mounted) return;
          _terminer(s == PaiementStatut.reussi ? _Etape.succes : _Etape.timeout);
        });
      }
    });
  }

  void _terminer(_Etape etape) {
    _timer?.cancel();
    _sub?.cancel();
    if (!mounted) return;
    setState(() => _etape = etape);
  }

  void _reessayer() {
    _timer?.cancel();
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
        title: Text(_loc.t('sponsor_title')),
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
              _loc.t('payment_failed_balance')),
          _Etape.timeout => _buildEchec(
              _loc.t('urgence_timeout'),
              _loc.t('payment_timeout_auto')),
        },
      ),
    );
  }

  Widget _buildFormulaire() {
    final peutPayer = _operateur != null && _telephoneComplet != null && !_loading;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // En-tête logement
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.photo != null && widget.photo!.isNotEmpty
                  ? Image.network(widget.photo!,
                      width: 60, height: 60, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoPlaceholder())
                  : _photoPlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.titre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        Text(_loc.t('sponsor_choose_duration'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ..._offres.map(_buildOffreCard),
        const SizedBox(height: 20),

        // Avantages
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appPrimaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvantageLigne(_loc.t('sponsor_benefit_1')),
              _AvantageLigne(_loc.t('sponsor_benefit_2')),
              _AvantageLigne(_loc.t('sponsor_benefit_3')),
              _AvantageLigne(_loc.t('sponsor_benefit_4')),
            ],
          ),
        ),
        const SizedBox(height: 20),

        OperateurSelector(
          telephoneInitial: _telephoneInitial,
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
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: peutPayer ? _payer : null,
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
              : Text(
                  '${_loc.t('sponsor_pay_prefix')} $_montant XAF via ${_labelOperateur(_operateur)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 13, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text(_loc.t('urgence_secure_payment'),
                style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
        if (kSimulationPaiement) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Text(
              _loc.t('common_simulation_mode'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  Widget _photoPlaceholder() => Builder(
    builder: (ctx) => Container(
      width: 60,
      height: 60,
      color: ctx.appPrimaryLight,
      child: const Icon(Icons.home, color: AppColors.primary),
    ),
  );

  Widget _buildOffreCard(_Offre offre) {
    final selected = _dureeCode == offre.code;
    // Traduction du titre selon le code
    final titreLabel = offre.code == '1s' ? _loc.t('sponsor_dur_1w')
        : offre.code == '2s' ? _loc.t('sponsor_dur_2w')
        : _loc.t('sponsor_dur_1m');
    // Traduction du badge
    final badgeLabel = offre.badge == null ? null
        : offre.badge == 'Recommandé' ? _loc.t('sponsor_recommended')
        : _loc.t('sponsor_best_value');

    return GestureDetector(
      onTap: () => setState(() => _dureeCode = offre.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? context.appPrimaryLight : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : context.appBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.primary : AppColors.textHint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
              Text(titreLabel,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primary : context.appTextPrimary)),
              if (badgeLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badgeLabel,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                ),
            ]),
          ),
          Text('${offre.montant} XAF',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.primary : context.appTextPrimary)),
        ]),
      ),
    );
  }

  Widget _buildAttente() {
    final progress = _restant / _kTimeoutSecondes;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
          Text(kSimulationPaiement ? _loc.t('common_simulation_progress') : _loc.t('sponsor_sent'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            kSimulationPaiement
                ? _loc.t('sponsor_sim_desc')
                : '${_loc.t('sponsor_confirm_geniuspay')} (${_telephoneComplet ?? ''}).\n${_loc.t('sponsor_timeout_msg')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: context.appTextSecondary),
          ),
          const SizedBox(height: 24),
          Text(_loc.t('common_checking'),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSucces() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.rocket_launch,
                    color: Colors.white, size: 56),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(_loc.t('sponsor_success'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            _loc.t('sponsor_success_desc'),
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('common_finish')),
          ),
        ],
      ),
    );
  }

  Widget _buildEchec(String titre, String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('common_retry')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_loc.t('common_cancel')),
          ),
        ],
      ),
    );
  }
}

class _AvantageLigne extends StatelessWidget {
  final String texte;
  const _AvantageLigne(this.texte);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texte,
                style: const TextStyle(fontSize: 13)),
          ),
        ]),
      );
}
