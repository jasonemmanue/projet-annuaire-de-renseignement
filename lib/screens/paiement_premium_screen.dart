import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/activation_email_service.dart';
import '../services/auth_service.dart';
import '../services/paiement_service.dart';
import '../widgets/operateur_selector.dart';
import '../widgets/silent_payment_webview.dart';
import '../l10n/app_localizations.dart';
import 'ios_activation_email_screen.dart';

// ============================================================
// FICHIER : lib/screens/paiement_premium_screen.dart
// Paiement du Pack Premium (200 XAF/mois) via Mobile Money.
// Opérateurs Cameroun : Orange Money, MTN Mobile Money.
// Flux : présentation → choix opérateur + n° +237 → Mobile Money
//        → écran d'attente (polling 120 s) → succès.
// ============================================================

const int _kMontantPremium = 200;
const String _kDevise = 'XAF';
const int _kTimeoutSecondes = 120;

enum _Etape { formulaire, attente, succes, echec, timeout }

class PaiementPremiumScreen extends StatefulWidget {
  const PaiementPremiumScreen({super.key});

  @override
  State<PaiementPremiumScreen> createState() => _PaiementPremiumScreenState();
}

class _PaiementPremiumScreenState extends State<PaiementPremiumScreen> {
  final _service = PaiementService.instance;
  late AppLocalizations _loc;

  _Etape _etape = _Etape.formulaire;
  bool _loading = false;
  String? _erreurForm;
  String? _reference;
  String? _checkoutUrl;
  bool _fallbackLance = false;

  // Renseignés par le widget OperateurSelector.
  String? _operateur;        // 'orange' | 'mtn'
  String? _telephoneComplet; // '+237XXXXXXXXX' ou null si invalide

  // Compte à rebours + écoute statut
  int _restant = _kTimeoutSecondes;
  Timer? _timer;
  Timer? _pollTimer;
  StreamSubscription<PaiementStatut>? _sub;

  @override
  void initState() {
    super.initState();
    // iOS : redirection vers activation par email (App Store 3.1.1)
    if (isExternalActivationRequired) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const IosActivationEmailScreen(
              type: ActivationType.premium,
              serviceLabel: 'Pack Premium (30 jours)',
            ),
          ),
        );
      });
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
    super.dispose();
  }

  String _labelOperateur(String? op) {
    switch (op) {
      case 'orange':
        return 'Orange Money';
      case 'mtn':
        return 'MTN Mobile Money';
      default:
        return 'Mobile Money';
    }
  }

  // ─── Lancer le paiement ───────────────────────────────────────────────────
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

    final result = await _service.initierPremium(
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
    _checkoutUrl = result.checkoutUrl;
    // Le WebView invisible (dans le body Stack) va déclencher l'USSD PawaPay
    // silencieusement. Fallback launchUrl à T+15s (voir _demarrerAttente).

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

    // (0) Fallback : ouvre le navigateur si le WebView invisible n'a pas
    //     suffi à déclencher l'USSD dans les 15 premières secondes.
    Timer(const Duration(seconds: 15), () async {
      if (!mounted || _etape != _Etape.attente || _fallbackLance) return;
      _fallbackLance = true;
      final s = await _service.verifierPaiementServeur(_reference!);
      if (!mounted || _etape != _Etape.attente) return;
      if (s == PaiementStatut.enAttente &&
          _checkoutUrl != null && _checkoutUrl!.isNotEmpty) {
        try {
          await launchUrl(Uri.parse(_checkoutUrl!),
              mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    });

    // (1) Écoute temps réel Firestore (mise à jour par le webhook s'il arrive)
    _sub = _service.watchStatut(_reference!).listen((statut) {
      if (!mounted) return;
      if (statut == PaiementStatut.reussi) {
        _terminer(_Etape.succes);
      } else if (statut == PaiementStatut.echoue) {
        _terminer(_Etape.echec);
      }
    });

    // (2) Vérification ACTIVE toutes les 5 s auprès du serveur
    //     (indépendante du webhook — c'est elle qui garantit l'activation).
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final s = await _service.verifierPaiementServeur(_reference!);
      if (!mounted) return;
      if (s == PaiementStatut.reussi) {
        _terminer(_Etape.succes);
      } else if (s == PaiementStatut.echoue) {
        _terminer(_Etape.echec);
      }
    });

    // (3) Compte à rebours visuel + dernière vérif au timeout
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restant--);
      if (_restant <= 0) {
        t.cancel();
        _service.verifierPaiementServeur(_reference!).then((s) {
          if (!mounted) return;
          if (s == PaiementStatut.reussi) {
            _terminer(_Etape.succes);
          } else {
            _terminer(_Etape.timeout);
          }
        });
      }
    });
  }

  void _terminer(_Etape etape) {
    _timer?.cancel();
    _pollTimer?.cancel();
    _sub?.cancel();
    if (!mounted) return;
    setState(() => _etape = etape);
    if (etape == _Etape.succes) {
      AuthService.instance.refreshCurrentUser();
    }
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

  // ─── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loc.t('premium_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
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
              _Etape.attente    => _buildAttente(),
              _Etape.succes     => _buildSucces(),
              _Etape.echec      => _buildResultatEchec(
                  titre: _loc.t('urgence_payment_failed'),
                  message: _loc.t('premium_payment_failed_wave'),
                ),
              _Etape.timeout    => _buildResultatEchec(
                  titre: _loc.t('urgence_timeout'),
                  message: _loc.t('premium_timeout_desc'),
                ),
            },
          ],
        ),
      ),
    );
  }

  // ── Section 1 + 2 + 3 : présentation, choix opérateur, bouton ─────────────
  Widget _buildFormulaire() {
    final peutPayer =
        _operateur != null && _telephoneComplet != null && !_loading;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildPackCard(),
        const SizedBox(height: 24),
        OperateurSelector(
          telephoneInitial: AuthService.instance.currentUser?.telephone,
          onChanged: (op, tel) {
            setState(() {
              _operateur = op;
              _telephoneComplet = tel;
            });
          },
        ),
        if (_erreurForm != null) ...[
          const SizedBox(height: 8),
          Text(_erreurForm!,
              style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: peutPayer ? _payer : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(
                  '${_loc.t('common_pay_prefix')} $_kMontantPremium $_kDevise via ${_labelOperateur(_operateur)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
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

  Widget _buildPackCard() {
    final avantages = [
      _loc.t('premium_benefit_1'),
      _loc.t('premium_benefit_2'),
      _loc.t('premium_benefit_3'),
      _loc.t('premium_benefit_4'),
      _loc.t('premium_benefit_5'),
      _loc.t('premium_benefit_6'),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('★ PREMIUM',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.black87)),
          ),
          const SizedBox(height: 16),
          ...avantages.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(a,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ),
                ]),
              )),
          const Divider(color: Colors.white24, height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('$_kMontantPremium $_kDevise',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(_loc.t('premium_per_month'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ── Section 4 : écran d'attente ───────────────────────────────────────────
  Widget _buildAttente() {
    final progress = _restant / _kTimeoutSecondes;
    return SingleChildScrollView(
      child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
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
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            kSimulationPaiement ? _loc.t('common_simulation_progress') : _loc.t('urgence_sent'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            kSimulationPaiement
                ? _loc.t('premium_sim_desc')
                : '${_loc.t('urgence_validate_payment')} ${_labelOperateur(_operateur)} ${_loc.t('premium_validate_on_phone')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: context.appTextSecondary),
          ),
          const SizedBox(height: 24),
          Text(_loc.t('common_checking'),
              style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    ),
    );
  }

  // ── Succès ──────────────────────────────────────────────────────────────────
  Widget _buildSucces() {
    return SingleChildScrollView(
      child: Padding(
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
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 64),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(_loc.t('premium_success'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            _loc.t('premium_success_desc'),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_loc.t('common_finish')),
          ),
        ],
      ),
    ),
    );
  }

  // ── Échec / timeout ──────────────────────────────────────────────────────
  Widget _buildResultatEchec(
      {required String titre, required String message}) {
    return SingleChildScrollView(
      child: Padding(
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
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appTextSecondary,
                  fontSize: 14,
                  height: 1.5)),
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
        ],
      ),
    ),
    );
  }
}

