import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/media_permission.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../legal/cgu_screen.dart';
import 'diag_otp_screen.dart';

// ============================================================================
// FICHIER : lib/screens/auth/login_screen.dart
//
// Authentification par email + mot de passe (Firebase Auth).
// Le numéro de téléphone demandé à l'inscription N'EST PAS vérifié : il sert de
// numéro Mobile Money par défaut pour les paiements. Aucun SMS n'est envoyé.
// ============================================================================

class LoginScreen extends StatefulWidget {
  final bool isInscription;
  const LoginScreen({super.key, this.isInscription = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isInscription ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ─── EN-TÊTE GRADIENT ──────────────────────────────
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
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                  ]),
                  GestureDetector(
                    onLongPress: kDebugMode
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DiagOtpScreen()),
                            )
                        : null,
                    child: Text(
                      l.t('login_space'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.t('login_tagline'),
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
                      Tab(text: l.t('login_tab_login')),
                      Tab(text: l.t('login_tab_register')),
                    ],
                  ),
                ],
              ),
            ),

            // ─── TABS ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _ConnexionTab(),
                  _InscriptionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ONGLET CONNEXION — email + mot de passe
// ============================================================================
class _ConnexionTab extends StatefulWidget {
  const _ConnexionTab();
  @override
  State<_ConnexionTab> createState() => _ConnexionTabState();
}

class _ConnexionTabState extends State<_ConnexionTab> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;
  String? _errorMessage;

  int _lockSeconds = 0;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _isLocked => _lockSeconds > 0;

  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSeconds = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (--_lockSeconds <= 0) { t.cancel(); _lockSeconds = 0; } });
    });
  }

  Future<void> _connexion() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    final result = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    _handleResult(result);
  }

  void _handleResult(AuthResult result) {
    final l = AppLocalizations.of(context);
    switch (result) {
      case AuthResult.success:
        Navigator.pop(context, true);
      case AuthResult.wrongCredentials:
        setState(() => _errorMessage = l.t('login_error_wrong_credentials'));
      case AuthResult.invalidEmail:
        setState(() => _errorMessage = l.t('login_error_invalid_email'));
      case AuthResult.userDisabled:
        setState(() => _errorMessage = l.t('login_error_disabled'));
      case AuthResult.tooManyAttempts:
        _startLockCountdown(AuthService.instance.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      case AuthResult.networkError:
        setState(() => _errorMessage = l.t('login_error_network'));
      case AuthResult.emailAlreadyUsed:
      case AuthResult.weakPassword:
        break;
    }
  }

  Future<void> _motDePasseOublie() async {
    final l = AppLocalizations.of(context);
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final envoyer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('login_forgot_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('login_forgot_desc'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: l.t('login_email')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('login_forgot_send')),
          ),
        ],
      ),
    );

    if (envoyer != true) return;
    final email = emailCtrl.text.trim();
    if (email.isEmpty) return;

    final result = await AuthService.instance.sendPasswordReset(email);
    if (!mounted) return;
    final ok = result == AuthResult.success;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l.t('login_forgot_sent') : l.t('login_error_invalid_email')),
      backgroundColor: ok ? Colors.green.shade700 : AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(l.t('login_welcome_back'),
                  style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: 12),
              _BandeauInfo(texte: l.t('login_reserved')),
              const SizedBox(height: 16),

              _ChampEmail(controller: _emailCtrl),
              const SizedBox(height: 12),
              _ChampMotDePasse(
                controller: _passwordCtrl,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
                textInputAction: TextInputAction.done,
                onSubmit: _connexion,
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _motDePasseOublie,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  child: Text(l.t('login_forgot_link'),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 4),
                _ErrorBanner(message: _errorMessage!),
                if (kDebugMode) const _DebugDiagBanner(),
              ],
              if (_isLocked) ...[
                const SizedBox(height: 12),
                _LockBanner(seconds: _lockSeconds),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: (_isLoading || _isLocked) ? null : _connexion,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  disabledBackgroundColor:
                      Theme.of(context).disabledColor.withValues(alpha: 0.2),
                ),
                child: _isLoading
                    ? const _Spinner()
                    : Text(l.t('login_signin'),
                        style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ONGLET INSCRIPTION — photo, identité, email, téléphone (paiement), mot de passe
// ============================================================================
class _InscriptionTab extends StatefulWidget {
  const _InscriptionTab();
  @override
  State<_InscriptionTab> createState() => _InscriptionTabState();
}

class _InscriptionTabState extends State<_InscriptionTab> {
  final _formKey = GlobalKey<FormState>();
  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _cguAcceptees = false;
  String? _errorMessage;
  XFile? _photo;

  int _lockSeconds = 0;
  Timer? _lockTimer;

  @override
  void dispose() {
    _lockTimer?.cancel();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _isLocked => _lockSeconds > 0;

  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSeconds = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (--_lockSeconds <= 0) { t.cancel(); _lockSeconds = 0; } });
    });
  }

  String get _fullPhone => '+237${_telCtrl.text.trim()}';

  Future<void> _pickPhoto(ImageSource source) async {
    final type = source == ImageSource.camera ? MediaType.camera : MediaType.photos;
    if (!await demanderPermissionMedia(context, type)) return;
    final img = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (img != null && mounted) setState(() => _photo = img);
  }

  Future<void> _inscription() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_cguAcceptees) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).t('login_cgu_required')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }
    final auth = AuthService.instance;
    setState(() { _isLoading = true; _errorMessage = null; });

    // 1) Création du compte (le téléphone devient le numéro de paiement par défaut).
    final result = await auth.register(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      nom: _nomCtrl.text.trim(),
      prenom: _prenomCtrl.text.trim(),
      telephone: _fullPhone,
    );
    if (!mounted) return;

    if (result != AuthResult.success) {
      setState(() => _isLoading = false);
      _handleResult(result);
      return;
    }

    // 2) Photo (optionnelle) : uploadée APRÈS création — l'uid est requis.
    if (_photo != null && auth.currentUser != null) {
      try {
        final urls = await StorageService.uploadMultiplePhotos(
          uid: auth.currentUser!.id,
          logementId: 'profile_${auth.currentUser!.id}',
          images: [_photo!],
        );
        if (urls.isNotEmpty) {
          await auth.updateProfile(photoUrl: urls.first);
        }
      } catch (_) {
        // Photo non bloquante : le compte est créé, elle se change au profil.
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).t('login_register_complete')),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
    Navigator.pop(context, true);
  }

  void _handleResult(AuthResult result) {
    final l = AppLocalizations.of(context);
    switch (result) {
      case AuthResult.emailAlreadyUsed:
        setState(() => _errorMessage = l.t('login_error_email_used'));
      case AuthResult.invalidEmail:
        setState(() => _errorMessage = l.t('login_error_invalid_email'));
      case AuthResult.weakPassword:
        setState(() => _errorMessage = l.t('login_error_weak_password'));
      case AuthResult.tooManyAttempts:
        _startLockCountdown(AuthService.instance.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      case AuthResult.networkError:
        setState(() => _errorMessage = l.t('login_error_network'));
      case AuthResult.success:
      case AuthResult.wrongCredentials:
      case AuthResult.userDisabled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _BandeauInfo(texte: l.t('login_reserved')),
              const SizedBox(height: 16),

              // ─── PHOTO ───────────────────────────────────────
              Center(
                child: Column(children: [
                  GestureDetector(
                    onTap: () => _pickPhoto(ImageSource.gallery),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage:
                          _photo != null ? FileImage(File(_photo!.path)) : null,
                      child: _photo == null
                          ? const Icon(Icons.person,
                              size: 44, color: AppColors.primary)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library, size: 16),
                      label: Text(l.t('login_gallery'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: Text(l.t('login_camera'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                  Text(l.t('login_profile_photo'),
                      style: AppTextStyles.caption
                          .copyWith(color: context.appTextSecondary)),
                ]),
              ),
              const SizedBox(height: 16),

              // ─── NOM / PRÉNOM ────────────────────────────────
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _prenomCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        InputDecoration(labelText: l.t('login_firstname')),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.t('form_required')
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _nomCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        InputDecoration(labelText: l.t('login_lastname')),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.t('form_required')
                        : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),

              // ─── EMAIL ───────────────────────────────────────
              _ChampEmail(controller: _emailCtrl),
              const SizedBox(height: 12),

              // ─── TÉLÉPHONE (numéro de paiement par défaut) ───
              TextFormField(
                controller: _telCtrl,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  labelText: l.t('login_phone'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                  prefixText: '+237 ',
                  hintText: l.t('login_phone_hint_otp'),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l.t('form_required');
                  // Mobiles camerounais : 9 chiffres commençant par 6 ou 2.
                  if (!RegExp(r'^[62]\d{8}$').hasMatch(v.trim())) {
                    return l.t('login_phone_invalid');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.info_outline, size: 13, color: context.appTextSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(l.t('login_phone_payment_info'),
                      style: AppTextStyles.caption
                          .copyWith(color: context.appTextSecondary)),
                ),
              ]),
              const SizedBox(height: 12),

              // ─── MOT DE PASSE + CONFIRMATION ─────────────────
              _ChampMotDePasse(
                controller: _passwordCtrl,
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
                isNew: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return l.t('form_required');
                  if (v.length < 6) return l.t('login_password_too_short');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _ChampMotDePasse(
                controller: _confirmCtrl,
                obscure: _obscureConfirm,
                onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                label: l.t('login_password_confirm'),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.isEmpty) return l.t('form_required');
                  if (v != _passwordCtrl.text) return l.t('login_password_mismatch');
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ─── CGU ─────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _cguAcceptees,
                    onChanged: (v) => setState(() => _cguAcceptees = v ?? false),
                    activeColor: AppColors.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CguScreen())),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 12, color: context.appTextSecondary),
                          children: [
                            TextSpan(text: l.t('login_terms')),
                            TextSpan(
                              text: l.t('consentement_cgu_link'),
                              style: const TextStyle(
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _errorMessage!),
                if (kDebugMode) const _DebugDiagBanner(),
              ],
              if (_isLocked) ...[
                const SizedBox(height: 12),
                _LockBanner(seconds: _lockSeconds),
              ],
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: (_isLoading || _isLocked) ? null : _inscription,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  disabledBackgroundColor:
                      Theme.of(context).disabledColor.withValues(alpha: 0.2),
                ),
                child: _isLoading
                    ? const _Spinner()
                    : Text(l.t('login_signup'),
                        style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CHAMPS RÉUTILISABLES
// ============================================================================

class _ChampEmail extends StatelessWidget {
  final TextEditingController controller;
  const _ChampEmail({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      inputFormatters: [
        // Un espace dans un email est toujours une faute de frappe ; l'interdire
        // évite l'erreur `invalid-email` renvoyée par Firebase.
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      decoration: InputDecoration(
        labelText: l.t('login_email'),
        prefixIcon: const Icon(Icons.email_outlined),
        hintText: 'nom@exemple.com',
      ),
      validator: (v) {
        final val = v?.trim() ?? '';
        if (val.isEmpty) return l.t('form_required');
        // Validation volontairement simple : Firebase reste l'autorité finale.
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(val)) {
          return l.t('login_error_invalid_email');
        }
        return null;
      },
    );
  }
}

class _ChampMotDePasse extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final String? label;
  final bool isNew;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmit;
  final String? Function(String?)? validator;

  const _ChampMotDePasse({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    this.label,
    this.isNew = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmit,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      autofillHints: [isNew ? AutofillHints.newPassword : AutofillHints.password],
      decoration: InputDecoration(
        labelText: label ?? l.t('login_password'),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20),
          onPressed: onToggle,
        ),
      ),
      validator: validator ??
          (v) => (v == null || v.isEmpty) ? l.t('form_required') : null,
    );
  }
}

/// Bandeau bleu d'information générique.
class _BandeauInfo extends StatelessWidget {
  final String texte;
  const _BandeauInfo({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texte,
              style: const TextStyle(color: AppColors.primary, fontSize: 12)),
        ),
      ]),
    );
  }
}

/// Bannière d'erreur rouge.
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.error, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bannière de verrouillage anti-brute-force avec compte à rebours.
class _LockBanner extends StatelessWidget {
  final int seconds;
  const _LockBanner({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final minutes = (seconds / 60).ceil();
    final retry = seconds > 60
        ? '${l.t('common_retry')} dans $minutes minute${minutes > 1 ? 's' : ''}.'
        : '${l.t('common_retry')} dans ${seconds}s.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_clock, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l.t('login_locked_prefix')}\n$retry',
              style: const TextStyle(
                  color: AppColors.error, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bannière de diagnostic (debug uniquement) — affiche le dernier code d'erreur
/// Firebase Auth et un accès à l'écran de diagnostic complet.
class _DebugDiagBanner extends StatelessWidget {
  const _DebugDiagBanner();

  @override
  Widget build(BuildContext context) {
    final code = AuthService.lastAuthError;
    if (code == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bug_report_outlined,
                color: Colors.orange.shade800, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${l.t('otp_diag_banner_title')} · code: $code',
                  style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiagOtpScreen()),
              ),
              icon: const Icon(Icons.open_in_new, size: 12),
              label: Text(l.t('otp_diag_more'),
                  style: const TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicateur de chargement compact pour les boutons.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
}
