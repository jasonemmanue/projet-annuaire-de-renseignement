import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ============================================================
// FICHIER : lib/screens/auth/login_screen.dart
// Authentification - Réservée aux prestataires (§1.2)
// Login + Inscription + Connexion sociale (§5.1)
// ============================================================

class LoginScreen extends StatefulWidget {
  final bool isInscription;

  const LoginScreen({super.key, this.isInscription = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _obscurePwd = true;
  bool _isLoading = false;

  final _loginFormKey = GlobalKey<FormState>();
  final _inscriptionFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.isInscription ? 1 : 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose(); _passwordCtrl.dispose();
    _nomCtrl.dispose(); _prenomCtrl.dispose(); _telCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── EN-TÊTE ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const Text(
                    'Espace Prestataire',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Gérez vos biens immobiliers',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    tabs: const [Tab(text: 'Connexion'), Tab(text: 'Inscription')],
                  ),
                ],
              ),
            ),

            // ─── CONTENU TABS ─────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _OngletConnexion(
                    formKey: _loginFormKey,
                    emailCtrl: _emailCtrl,
                    passwordCtrl: _passwordCtrl,
                    obscurePwd: _obscurePwd,
                    isLoading: _isLoading,
                    onTogglePwd: () => setState(() => _obscurePwd = !_obscurePwd),
                    onLogin: _connexion,
                    onSocial: _connexionSociale,
                    onForgotPwd: () => _afficherReinitialisationMdp(context),
                  ),
                  _OngletInscription(
                    formKey: _inscriptionFormKey,
                    nomCtrl: _nomCtrl,
                    prenomCtrl: _prenomCtrl,
                    emailCtrl: _emailCtrl,
                    telCtrl: _telCtrl,
                    passwordCtrl: _passwordCtrl,
                    obscurePwd: _obscurePwd,
                    isLoading: _isLoading,
                    onTogglePwd: () => setState(() => _obscurePwd = !_obscurePwd),
                    onInscrire: _inscription,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connexion() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    // TODO: Intégrer Firebase Auth / API REST
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context); // Retour à l'écran principal
    }
  }

  Future<void> _inscription() async {
    if (!_inscriptionFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context);
    }
  }

  void _connexionSociale(String provider) {
    // TODO: Intégrer google_sign_in / facebook_auth (§5.1 - inscription simplifiée)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connexion $provider bientôt disponible'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _afficherReinitialisationMdp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mot de passe oublié', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            const Text('Entrez votre email pour recevoir un lien de réinitialisation.', style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            TextFormField(
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('Envoyer le lien'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// ONGLET CONNEXION
// ----------------------------------------------------------
class _OngletConnexion extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl, passwordCtrl;
  final bool obscurePwd, isLoading;
  final VoidCallback onTogglePwd, onLogin, onForgotPwd;
  final ValueChanged<String> onSocial;

  const _OngletConnexion({
    required this.formKey, required this.emailCtrl, required this.passwordCtrl,
    required this.obscurePwd, required this.isLoading, required this.onTogglePwd,
    required this.onLogin, required this.onSocial, required this.onForgotPwd,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) => v!.isEmpty || !v.contains('@') ? 'Email invalide' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePwd,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) => v!.length < 6 ? 'Au moins 6 caractères' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onForgotPwd,
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: isLoading ? null : onLogin,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Se connecter', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou continuer avec', style: AppTextStyles.caption)),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 16),
            // Connexion sociale (§5.1 - réduction frictions)
            Row(children: [
              Expanded(child: _BoutonSocial(label: 'Google', emoji: '🔴', onTap: () => onSocial('Google'))),
              const SizedBox(width: 12),
              Expanded(child: _BoutonSocial(label: 'Facebook', emoji: '🔵', onTap: () => onSocial('Facebook'))),
            ]),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// ONGLET INSCRIPTION
// ----------------------------------------------------------
class _OngletInscription extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nomCtrl, prenomCtrl, emailCtrl, telCtrl, passwordCtrl;
  final bool obscurePwd, isLoading;
  final VoidCallback onTogglePwd, onInscrire;

  const _OngletInscription({
    required this.formKey, required this.nomCtrl, required this.prenomCtrl,
    required this.emailCtrl, required this.telCtrl, required this.passwordCtrl,
    required this.obscurePwd, required this.isLoading, required this.onTogglePwd,
    required this.onInscrire,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Bandeau info (§1.2 - compte réservé prestataires)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Le compte est réservé aux propriétaires et agences.\nLes clients n\'ont pas besoin de compte.',
                      style: TextStyle(color: AppColors.primary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(
                controller: prenomCtrl,
                decoration: const InputDecoration(labelText: 'Prénom *'),
                validator: (v) => v!.isEmpty ? 'Requis' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: nomCtrl,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (v) => v!.isEmpty ? 'Requis' : null,
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email *', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) => v!.isEmpty || !v.contains('@') ? 'Email invalide' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone *',
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: '+237 6XX XXX XXX',
                prefixText: '+237 ',
              ),
              validator: (v) => v!.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePwd,
              decoration: InputDecoration(
                labelText: 'Mot de passe *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) => v!.length < 6 ? 'Au moins 6 caractères' : null,
            ),
            const SizedBox(height: 20),
            // CGU
            const Row(
              children: [
                Icon(Icons.check_box_outlined, color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text("En créant un compte, j'accepte les conditions d'utilisation et la politique de confidentialité.",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : onInscrire,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Créer mon compte gratuit', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// BOUTON CONNEXION SOCIALE
// ----------------------------------------------------------
class _BoutonSocial extends StatelessWidget {
  final String label;
  final String emoji;
  final VoidCallback onTap;

  const _BoutonSocial({required this.label, required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}