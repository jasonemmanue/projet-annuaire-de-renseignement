import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/paiement_service.dart';
import '../services/paiement_debug_log.dart';
import '../widgets/operateur_selector.dart';
import '../widgets/silent_payment_webview.dart';
import '../l10n/app_localizations.dart';

// ============================================================
// FICHIER : lib/screens/paiement_publication_screen.dart
// Paiement des frais de publication d'une annonce (commission %).
// Réutilise PaiementService.initierSponsorisation : le logement brouillon
// existe déjà (paymentPending: true), le webhook active disponible: true
// et applique la sponsorisation 30 jours.
//
// Pop(true)  → paiement OK, annonce publiée + sponsorisée 30 j
// Pop(false) → paiement échoué/annulé, le brouillon doit être supprimé
// ============================================================

const String _kDevise = 'XAF';
const int _kTimeoutSecondes = 120;

enum _Etape { formulaire, attente, succes, echec, timeout }

/// Callback d'initiation : renvoie le résultat (référence transaction).
typedef InitierPaiementCb = Future<PaiementInitResult> Function({
  required String telephone,
  required String operateur,
});

class PaiementPublicationScreen extends StatefulWidget {
  final String logementId;
  final String titreAnnonce;
  final int montant;
  // Paramètres optionnels pour réutiliser l'écran (ex. publicité).
  final String titreEcran;
  final String dureeLabel;
  final InitierPaiementCb? initierPersonnalise;
  final String boutonLabel;
  final String succesMessage;

  const PaiementPublicationScreen({
    super.key,
    required this.logementId,
    required this.titreAnnonce,
    required this.montant,
    this.titreEcran = 'Frais de publication',
    this.dureeLabel =
        'Inclut la mise en avant de votre annonce pendant 30 jours.',
    this.initierPersonnalise,
    this.boutonLabel = 'Payer et publier l\'annonce',
    this.succesMessage =
        'Votre annonce est maintenant publiée et mise en avant pendant 30 jours.',
  });

  @override
  State<PaiementPublicationScreen> createState() =>
      _PaiementPublicationScreenState();
}

class _PaiementPublicationScreenState extends State<PaiementPublicationScreen> {
  final _service = PaiementService.instance;
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

  Future<void> _payer() async {
    if (_operateur == null) {
      setState(() => _erreurForm = _loc.t('urgence_operator_hint'));
      return;
    }
    if (_telephoneComplet == null) {
      setState(() => _erreurForm = _loc.t('urgence_invalid_number'));
      return;
    }
    PaiementDebugLog.instance.clear();
    PaiementDebugLog.instance.info('=== NOUVELLE TENTATIVE ===');
    PaiementDebugLog.instance.info('Opérateur: $_operateur | Tél: $_telephoneComplet');
    PaiementDebugLog.instance.info('Montant: ${widget.montant} XAF | logementId: ${widget.logementId}');
    setState(() {
      _erreurForm = null;
      _loading = true;
    });

    final result = widget.initierPersonnalise != null
        ? await widget.initierPersonnalise!(
            telephone: _telephoneComplet!,
            operateur: _operateur!,
          )
        : await _service.initierSponsorisation(
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
    _checkoutUrl = result.checkoutUrl;

    // Le WebView invisible (monté dans le Stack du body dès que _etape passe
    // à attente) va charger checkoutUrl et exécuter son JavaScript, ce qui
    // déclenche l'USSD PawaPay sur le téléphone du client.
    // Aucun navigateur externe n'est ouvert → totalement invisible.
    // Fallback launchUrl à T+15s si le WebView n'a pas suffi (voir _demarrerAttente).

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

    _sub = _service.watchStatut(_reference!).listen((statut) {
      if (!mounted) return;
      if (statut == PaiementStatut.reussi) {
        _terminer(_Etape.succes);
      } else if (statut == PaiementStatut.echoue) {
        _terminer(_Etape.echec);
      }
    });

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

    // Fallback : si le WebView invisible n'a pas suffi à déclencher l'USSD
    // dans les 15 secondes, on ouvre la page GeniusPay dans le navigateur
    // externe. Ce cas ne devrait quasiment jamais arriver car le WebView
    // exécute le JS comme un vrai navigateur.
    Timer(const Duration(seconds: 15), () async {
      if (!mounted || _etape != _Etape.attente || _fallbackLance) return;
      _fallbackLance = true;
      final s = await _service.verifierPaiementServeur(_reference!);
      if (!mounted || _etape != _Etape.attente) return;
      if (s == PaiementStatut.enAttente &&
          _checkoutUrl != null &&
          _checkoutUrl!.isNotEmpty) {
        try {
          await launchUrl(
            Uri.parse(_checkoutUrl!),
            mode: LaunchMode.externalApplication,
          );
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
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_etape == _Etape.attente) {
          return false; // bloque la sortie pendant le paiement
        }
        if (_etape == _Etape.succes) {
          Navigator.pop(context, true);
        } else {
          Navigator.pop(context, false);
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.titreEcran),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: _etape != _Etape.attente,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              // WebView invisible qui déclenche l'USSD PawaPay silencieusement.
              // Ne prend qu'un pixel, opacity 0 → l'utilisateur ne le voit pas.
              if (_checkoutUrl != null &&
                  _checkoutUrl!.isNotEmpty &&
                  _etape == _Etape.attente)
                Positioned(
                  top: 0,
                  left: 0,
                  child: SilentPaymentWebView(url: _checkoutUrl!),
                ),
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildEtape(),
                    ),
                  ),
                  if (kDebugPaiement)
                    const SizedBox(
                      height: 225,
                      child: _DebugLogPanel(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEtape() {
    switch (_etape) {
      case _Etape.formulaire:
        return _buildFormulaire();
      case _Etape.attente:
        return _buildAttente();
      case _Etape.succes:
        return _buildSucces();
      case _Etape.echec:
        return _buildEchec();
      case _Etape.timeout:
        return _buildTimeout();
    }
  }

  Widget _buildFormulaire() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Récap
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Annonce',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 4),
              Text(widget.titreAnnonce,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('Montant à payer',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12)),
              const SizedBox(height: 4),
              Text('${widget.montant} $_kDevise',
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary)),
              const SizedBox(height: 8),
              Text(widget.dureeLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OperateurSelector(
          onChanged: (op, tel) => setState(() {
            _operateur = op;
            _telephoneComplet = tel;
            _erreurForm = null;
          }),
        ),
        if (_erreurForm != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_erreurForm!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _payer,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_outline),
            label: Text(
                _loading ? 'Initiation...' : widget.boutonLabel,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildAttente() {
    final mins = (_restant / 60).floor();
    final secs = _restant % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 24),
        Text(
          'Vérifiez votre téléphone — composez le code ${_labelOperateur(_operateur)} pour valider ${widget.montant} $_kDevise.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Text('Temps restant : ${mins}m${secs.toString().padLeft(2, '0')}s',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 12),
        const Text(
            'Ne fermez pas cette page.\nL\'annonce sera publiée automatiquement après confirmation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textHint)),
      ],
    );
  }

  Widget _buildSucces() {
    return Column(children: [
      const SizedBox(height: 24),
      Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
            color: AppColors.success, shape: BoxShape.circle),
        child:
            const Icon(Icons.check, color: Colors.white, size: 48),
      ),
      const SizedBox(height: 20),
      const Text('Paiement confirmé !',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Text(widget.succesMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Continuer',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  Widget _buildEchec() {
    return _MsgEtat(
      icon: Icons.close,
      iconColor: AppColors.error,
      titre: 'Paiement échoué',
      message:
          'Le paiement n\'a pas pu être validé. L\'annonce n\'a pas été publiée. Réessayez.',
      action: () => Navigator.pop(context, false),
      actionLabel: 'Retour',
    );
  }

  Widget _buildTimeout() {
    return _MsgEtat(
      icon: Icons.timer_off,
      iconColor: AppColors.warning,
      titre: 'Délai dépassé',
      message:
          'Aucune confirmation reçue. Si vous avez validé le paiement, il sera reflété sous peu — sinon l\'annonce ne sera pas publiée.',
      action: () => Navigator.pop(context, false),
      actionLabel: 'Retour',
    );
  }
}

// ============================================================
// Panneau de logs diagnostic (visible uniquement si kDebugPaiement = true)
// ============================================================

class _DebugLogPanel extends StatefulWidget {
  const _DebugLogPanel();

  @override
  State<_DebugLogPanel> createState() => _DebugLogPanelState();
}

class _DebugLogPanelState extends State<_DebugLogPanel> {
  final _scrollCtrl = ScrollController();
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    PaiementDebugLog.instance.addListener(_onNewLog);
  }

  @override
  void dispose() {
    PaiementDebugLog.instance.removeListener(_onNewLog);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNewLog() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copier() {
    final text = PaiementDebugLog.instance.toText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiés dans le presse-papier'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = PaiementDebugLog.instance.entries;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // En-tête du panneau
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00FF88),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'LOGS DIAGNOSTIC PAIEMENT',
                  style: TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length} entrées',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 10),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _copier,
                  child: const Text(
                    'COPIER',
                    style: TextStyle(
                      color: Color(0xFF90CAF9),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    PaiementDebugLog.instance.clear();
                    setState(() {});
                  },
                  child: const Text(
                    'VIDER',
                    style: TextStyle(
                      color: Color(0xFFFFCC80),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_more : Icons.expand_less,
                  color: const Color(0xFF888888),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        // Corps scrollable
        if (_expanded)
          Container(
            height: 180,
            color: const Color(0xFF0D0D1A),
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'En attente d\'activité…',
                      style: TextStyle(color: Color(0xFF555566), fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: '${e.timestamp} ',
                                style: const TextStyle(
                                    color: Color(0xFF555566)),
                              ),
                              TextSpan(
                                text: '[${e.icon}] ',
                                style: TextStyle(
                                    color: e.color,
                                    fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: e.message,
                                style: TextStyle(color: e.color),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

class _MsgEtat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String titre;
  final String message;
  final VoidCallback action;
  final String actionLabel;

  const _MsgEtat({
    required this.icon,
    required this.iconColor,
    required this.titre,
    required this.message,
    required this.action,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 24),
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 48),
      ),
      const SizedBox(height: 20),
      Text(titre,
          style:
              const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Text(message,
          textAlign: TextAlign.center,
          style:
              const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child:
              Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}
