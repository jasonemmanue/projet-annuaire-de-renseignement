import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';

// ============================================================
// FICHIER : lib/screens/auth/login_screen.dart
// ✅ Anti-brute-force : 3 tentatives → 30s | 5 tentatives → 5min
// ✅ Compteur visible "Réessayer dans Xs..."
// ✅ Message de verrouillage rouge
// ✅ "Mot de passe oublié ?" dès la 2ème tentative échouée
// ✅ Dialog réinitialisation mot de passe fonctionnel
// ✅ Connexion email/mot de passe uniquement
// ✅ Inscription avec photo de profil
// ============================================================

class LoginScreen extends StatefulWidget {
  final bool isInscription;
  const LoginScreen({super.key, this.isInscription = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _obscurePwd = true;
  bool _isLoading  = false;

  final _loginFormKey      = GlobalKey<FormState>();
  final _inscriptionFormKey = GlobalKey<FormState>();

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nomCtrl      = TextEditingController();
  final _prenomCtrl   = TextEditingController();
  final _telCtrl      = TextEditingController();

  // Photo de profil sélectionnée à l'inscription
  XFile?  _photoSelectionnee;

  // ─── ÉTAT ANTI-BRUTE-FORCE ──────────────────────────────────
  /// Secondes restantes avant déblocage (0 = pas bloqué)
  int     _countdownSeconds = 0;
  Timer?  _countdownTimer;
  /// Afficher le lien "Mot de passe oublié ?" (dès la 2ème tentative)
  bool    _showForgotPassword = false;
  /// Message de verrouillage à afficher sous le bouton
  String? _lockMessage;

  late AppLocalizations _l;

  // ─── INITIALISATION ────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isInscription ? 1 : 0,
    );
    _syncBruteForceUI();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
  }

  /// Synchronise l'UI avec l'état persisté dans AuthService.
  void _syncBruteForceUI() {
    final auth = AuthService.instance;

    if (auth.failedAttempts >= 2) {
      setState(() => _showForgotPassword = true);
    }

    if (auth.isBlocked) {
      _startCountdown(auth.remainingLockDuration.inSeconds);
    }
  }

  /// Lance le compte à rebours de déverrouillage.
  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _countdownSeconds = seconds;
    _updateLockMessage();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownSeconds--;
        _updateLockMessage();
        if (_countdownSeconds <= 0) {
          timer.cancel();
          _countdownSeconds = 0;
          _lockMessage = null;
        }
      });
    });
  }

  void _updateLockMessage() {
    if (_countdownSeconds <= 0) {
      _lockMessage = null;
      return;
    }
    final auth = AuthService.instance;
    if (auth.failedAttempts >= 5 || _countdownSeconds > 60) {
      final minutes = (_countdownSeconds / 60).ceil();
      _lockMessage =
      'Trop de tentatives. Votre compte est temporairement verrouillé.\n'
          'Réessayez dans $minutes minute${minutes > 1 ? 's' : ''}.';
    } else {
      _lockMessage =
      'Trop de tentatives. Votre compte est temporairement verrouillé.\n'
          'Réessayez dans ${_countdownSeconds}s.';
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  // ─── PHOTO ────────────────────────────────────────────────

  Future<void> _choisirPhoto() async {
    final picker = ImagePicker();
    final image  = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (image != null) setState(() => _photoSelectionnee = image);
  }

  Future<void> _prendrePhoto() async {
    final picker = ImagePicker();
    final image  = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 80);
    if (image != null) setState(() => _photoSelectionnee = image);
  }

  // ─── CONNEXION AVEC ANTI-BRUTE-FORCE ─────────────────────

  Future<void> _connexion() async {
    if (!_loginFormKey.currentState!.validate()) return;

    // Vérification côté UI (double-sécurité)
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }

    setState(() => _isLoading = true);

    final result = await auth.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AuthResult.success:
      // ✅ Succès : on réinitialise toute l'UI brute-force
        setState(() {
          _showForgotPassword = false;
          _lockMessage        = null;
          _countdownSeconds   = 0;
        });
        _countdownTimer?.cancel();
        Navigator.pop(context, true);

      case AuthResult.wrongCredentials:
      // Mise à jour du cache (AuthService a déjà incrémenté)
        final attempts = auth.failedAttempts;

        // Afficher "Mot de passe oublié ?" dès la 2ème tentative
        if (attempts >= 2) {
          setState(() => _showForgotPassword = true);
        }

        if (auth.isBlocked) {
          _startCountdown(auth.remainingLockDuration.inSeconds);
          setState(() {}); // Force rebuild pour désactiver le bouton
        } else {
          final restant = 3 - attempts;
          final pluriel = restant > 1 ? 's' : '';
          _showSnack(
            restant > 0
                ? 'Identifiant ou mot de passe incorrect. '
                'Il vous reste $restant tentative$pluriel.'
                : 'Identifiant ou mot de passe incorrect.',
            Colors.red.shade700,
          );
        }

      case AuthResult.tooManyAttempts:
        _startCountdown(auth.remainingLockDuration.inSeconds);
        setState(() {});

      case AuthResult.emailAlreadyUsed:
        _showSnack(_l.t('login_error_email_used'), Colors.red.shade700);

      case AuthResult.networkError:
        _showSnack(_l.t('login_error_network'), Colors.orange.shade700);
    }
  }

  // ─── INSCRIPTION ──────────────────────────────────────────

  Future<void> _inscription() async {
    if (!_inscriptionFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    String? photoUrl;
    if (_photoSelectionnee != null) {
      try {
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        final urls   = await StorageService.uploadMultiplePhotos(
          uid:        tempId,
          logementId: 'profile_$tempId',
          images:     [_photoSelectionnee!],
        );
        if (urls.isNotEmpty) photoUrl = urls.first;
      } catch (_) {
        // Photo non bloquante
      }
    }

    final result = await AuthService.instance.register(
      email:     _emailCtrl.text.trim(),
      password:  _passwordCtrl.text,
      nom:       _nomCtrl.text.trim(),
      prenom:    _prenomCtrl.text.trim(),
      telephone: _telCtrl.text.trim(),
      photoUrl:  photoUrl,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AuthResult.success:
        _showSnack(_l.t('login_success_register'), Colors.green.shade700);
        _tabController.animateTo(0);

      case AuthResult.emailAlreadyUsed:
      case AuthResult.wrongCredentials:
        _showSnack(_l.t('login_error_already_registered'), Colors.red.shade700);

      case AuthResult.networkError:
        _showSnack(_l.t('login_error_network_register'), Colors.orange.shade700);

      case AuthResult.tooManyAttempts:
        break; // Ne peut pas survenir à l'inscription
    }
  }

  // ─── UI HELPERS ───────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  /// Calcule le libellé du bouton "Réessayer dans Xs..."
  String get _buttonLabel {
    if (_countdownSeconds > 0) {
      return '${_l.t('common_retry')} dans ${_countdownSeconds}s';
    }
    return _l.t('login_button');
  }

  bool get _isButtonDisabled => _isLoading || _countdownSeconds > 0;

  // ─── DIALOG RESET MOT DE PASSE ───────────────────────────

  void _afficherReinitialisationMdp(BuildContext context) {
    final resetEmailCtrl = TextEditingController(
      text: _emailCtrl.text.trim(), // Pré-remplir avec l'email saisi
    );
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> envoyerLien() async {
              final email = resetEmailCtrl.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_l.t('login_forgot_empty_email')),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }

              setModalState(() => isSubmitting = true);
              final result =
              await AuthService.instance.sendPasswordReset(email);
              if (!ctx.mounted) return;
              setModalState(() => isSubmitting = false);

              switch (result) {
                case AuthResult.success:
                  Navigator.pop(ctx);
                  _showSnack(
                    '${_l.t('login_forgot_sent')} $email. ${_l.t('login_forgot_check_spam')}',
                    Colors.green.shade700,
                  );

                case AuthResult.wrongCredentials:
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_l.t('login_forgot_no_account')),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                  ));

                case AuthResult.networkError:
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_l.t('login_error_network_register')),
                    backgroundColor: Colors.orange.shade700,
                    behavior: SnackBarBehavior.floating,
                  ));

                default:
                  break;
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poignée visuelle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(_l.t('login_forgot_title'), style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  Text(
                    _l.t('login_forgot_subtitle'),
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: _l.t('login_email_field'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isSubmitting ? null : envoyerLien,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48)),
                    child: isSubmitting
                        ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : Text(_l.t('login_forgot_send')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── BUILD ────────────────────────────────────────────────

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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                  Text(
                    _l.t('login_space'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _l.t('login_tagline'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    tabs: [
                      Tab(text: _l.t('login_tab_login')),
                      Tab(text: _l.t('login_tab_register')),
                    ],
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
                    formKey:            _loginFormKey,
                    emailCtrl:          _emailCtrl,
                    passwordCtrl:       _passwordCtrl,
                    obscurePwd:         _obscurePwd,
                    isLoading:          _isLoading,
                    isButtonDisabled:   _isButtonDisabled,
                    buttonLabel:        _buttonLabel,
                    lockMessage:        _lockMessage,
                    showForgotPassword: _showForgotPassword,
                    onTogglePwd: () =>
                        setState(() => _obscurePwd = !_obscurePwd),
                    onLogin:      _connexion,
                    onForgotPwd:  () =>
                        _afficherReinitialisationMdp(context),
                  ),
                  _OngletInscription(
                    formKey:            _inscriptionFormKey,
                    nomCtrl:            _nomCtrl,
                    prenomCtrl:         _prenomCtrl,
                    emailCtrl:          _emailCtrl,
                    telCtrl:            _telCtrl,
                    passwordCtrl:       _passwordCtrl,
                    obscurePwd:         _obscurePwd,
                    isLoading:          _isLoading,
                    photoSelectionnee:  _photoSelectionnee,
                    onTogglePwd: () =>
                        setState(() => _obscurePwd = !_obscurePwd),
                    onInscrire:         _inscription,
                    onChoisirPhoto:     _choisirPhoto,
                    onPrendrePhoto:     _prendrePhoto,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// ONGLET CONNEXION
// ✅ Bouton désactivé avec countdown
// ✅ Message de verrouillage rouge
// ✅ "Mot de passe oublié ?" conditionnel
// ==============================================================
class _OngletConnexion extends StatelessWidget {
  final GlobalKey<FormState>     formKey;
  final TextEditingController    emailCtrl, passwordCtrl;
  final bool                     obscurePwd, isLoading, isButtonDisabled;
  final bool                     showForgotPassword;
  final String                   buttonLabel;
  final String?                  lockMessage;
  final VoidCallback             onTogglePwd, onLogin, onForgotPwd;

  const _OngletConnexion({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePwd,
    required this.isLoading,
    required this.isButtonDisabled,
    required this.buttonLabel,
    required this.showForgotPassword,
    required this.lockMessage,
    required this.onTogglePwd,
    required this.onLogin,
    required this.onForgotPwd,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ─── Email ─────────────────────────────────────────
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: l.t('login_email'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 12),

            // ─── Mot de passe ──────────────────────────────────
            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePwd,
              decoration: InputDecoration(
                labelText: l.t('login_password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) =>
              (v == null || v.length < 6)
                  ? l.t('login_password_hint')
                  : null,
            ),

            // ─── "Mot de passe oublié ?" (dès la 2ème tentative) ─
            if (showForgotPassword)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onForgotPwd,
                  child: Text(l.t('login_forgot_password')),
                ),
              )
            else
              const SizedBox(height: 8),

            const SizedBox(height: 8),

            // ─── Message de verrouillage ───────────────────────
            if (lockMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_clock,
                        color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lockMessage!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ─── Bouton connexion ──────────────────────────────
            ElevatedButton(
              onPressed: isButtonDisabled ? null : onLogin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                // Couleur atténuée quand bloqué
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: isLoading
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : Text(buttonLabel, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// ONGLET INSCRIPTION avec photo de profil
// ✅ Champ téléphone avec préfixe +237
// ✅ Photo de profil optionnelle
// ==============================================================
class _OngletInscription extends StatelessWidget {
  final GlobalKey<FormState>   formKey;
  final TextEditingController  nomCtrl, prenomCtrl, emailCtrl, telCtrl,
      passwordCtrl;
  final bool                   obscurePwd, isLoading;
  final XFile?                 photoSelectionnee;
  final VoidCallback           onTogglePwd, onInscrire, onChoisirPhoto,
      onPrendrePhoto;

  const _OngletInscription({
    required this.formKey,
    required this.nomCtrl,
    required this.prenomCtrl,
    required this.emailCtrl,
    required this.telCtrl,
    required this.passwordCtrl,
    required this.obscurePwd,
    required this.isLoading,
    required this.photoSelectionnee,
    required this.onTogglePwd,
    required this.onInscrire,
    required this.onChoisirPhoto,
    required this.onPrendrePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.t('login_reserved'),
                      style: const TextStyle(color: AppColors.primary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── PHOTO DE PROFIL ─────────────────────────────
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: onChoisirPhoto,
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: photoSelectionnee != null
                          ? AssetImage(photoSelectionnee!.path)
                      as ImageProvider
                          : null,
                      child: photoSelectionnee == null
                          ? const Icon(Icons.person,
                          size: 44, color: AppColors.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: onChoisirPhoto,
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: Text(l.t('login_gallery'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: onPrendrePhoto,
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: Text(l.t('login_camera'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  Text(
                    l.t('login_profile_photo'),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: prenomCtrl,
                  decoration: InputDecoration(labelText: l.t('login_firstname')),
                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: nomCtrl,
                  decoration: InputDecoration(labelText: l.t('login_lastname')),
                  validator: (v) => v!.isEmpty ? 'Requis' : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),

            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l.t('login_email_field'),
                prefixIcon: const Icon(Icons.email_outlined),
              ),
              validator: (v) =>
              (v == null || v.isEmpty) ? 'Email requis' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.t('login_phone'),
                prefixIcon: const Icon(Icons.phone_outlined),
                prefixText: '+237 ',
                hintText: '667546786',
              ),
              validator: (v) => v!.isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePwd,
              decoration: InputDecoration(
                labelText: l.t('login_password_field'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) =>
              v!.length < 6 ? l.t('login_password_hint') : null,
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                const Icon(Icons.check_box_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.t('login_terms'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: isLoading ? null : onInscrire,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : Text(l.t('login_create_account'),
                  style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}