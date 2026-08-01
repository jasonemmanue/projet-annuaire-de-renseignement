import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/activation_email_service.dart';
import '../theme/app_theme.dart';

/// Écran unique iOS remplaçant les 6 flux de paiement (App Store 3.1.1).
///
/// Ne montre aucune mention de prix, paiement, XAF, MTN/Orange, GeniusPay.
/// Se contente de demander une adresse email et d'appeler
/// [ActivationEmailService.envoyerLien] — le paiement se fait ensuite sur
/// une page web hors de l'app.
class IosActivationEmailScreen extends StatefulWidget {
  final ActivationType type;
  final String? targetId;
  final Map<String, dynamic>? params;

  /// Libellé du service pour l'écran (ex. "Publication de votre annonce").
  final String serviceLabel;

  const IosActivationEmailScreen({
    super.key,
    required this.type,
    required this.serviceLabel,
    this.targetId,
    this.params,
  });

  @override
  State<IosActivationEmailScreen> createState() =>
      _IosActivationEmailScreenState();
}

class _IosActivationEmailScreenState extends State<IosActivationEmailScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _envoi = false;
  bool _envoye = false;

  @override
  void initState() {
    super.initState();
    // Pré-remplit avec l'email Firebase Auth si disponible.
    final u = FirebaseAuth.instance.currentUser;
    if (u?.email != null && u!.email!.isNotEmpty) {
      _emailCtrl.text = u.email!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _envoi = true);
    final result = await ActivationEmailService.instance.envoyerLien(
      type: widget.type,
      email: _emailCtrl.text.trim(),
      targetId: widget.targetId,
      params: widget.params,
    );
    if (!mounted) return;
    setState(() => _envoi = false);
    if (result.success) {
      setState(() => _envoye = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('ios_activation_title')),
        elevation: 0,
      ),
      body: SafeArea(
        child: _envoye ? _buildConfirmation(l) : _buildForm(l),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 88,
              height: 88,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            Text(
              l.t('ios_activation_heading'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.serviceLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.t('ios_activation_description'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodyMedium?.color,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l.t('ios_activation_email_label'),
                hintText: 'nom@exemple.com',
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return l.t('ios_activation_email_required');
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) {
                  return l.t('ios_activation_email_invalid');
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _envoi ? null : _envoyer,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _envoi
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l.t('ios_activation_send_button'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              l.t('ios_activation_footer'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmation(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: Color(0x1F2D8A4E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 60,
              color: Color(0xFF2D8A4E),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l.t('ios_activation_success_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.t('ios_activation_success_body').replaceAll(
                  '{email}',
                  _emailCtrl.text.trim(),
                ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).textTheme.bodyMedium?.color,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 40,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l.t('ios_activation_success_done')),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper de routage : détecte iOS et redirige vers l'écran d'activation email.
// À appeler au début des 6 flux de paiement.
// ─────────────────────────────────────────────────────────────────────────────

/// Vrai si l'app doit utiliser le flow email/web (iOS) au lieu du paiement
/// intégré (Android).
bool get isExternalActivationRequired => Platform.isIOS;

/// Route l'utilisateur vers l'écran d'activation email au lieu du paiement
/// intégré. Retourne `true` si la navigation a eu lieu (iOS), `false` sinon.
///
/// [serviceLabel] est affiché à l'utilisateur (ex. "Publication de votre annonce").
/// Aucune mention de prix.
Future<bool> routeToActivationEmailIfNeeded(
  BuildContext context, {
  required ActivationType type,
  required String serviceLabel,
  String? targetId,
  Map<String, dynamic>? params,
}) async {
  if (!isExternalActivationRequired) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => IosActivationEmailScreen(
        type: type,
        serviceLabel: serviceLabel,
        targetId: targetId,
        params: params,
      ),
      fullscreenDialog: true,
    ),
  );
  return true;
}
