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

// ==============================================================
// ÉCRAN DE CONNEXION / INSCRIPTION — EMAIL + MOT DE PASSE
// Le numéro de téléphone reste demandé à l'inscription comme
// coordonnée de contact (affichée aux visiteurs) mais n'authentifie pas.
// Un email de vérification est envoyé à l'inscription.
// ==============================================================

/// Valide un email de façon simple mais robuste.
bool _isValidEmail(String v) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

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

// ==============================================================
// TAB CONNEXION — email + mot de passe
// ==============================================================
class _ConnexionTab extends StatefulWidget {
  const _ConnexionTab();
  @override
  State<_ConnexionTab> createState() => _ConnexionTabState();
}

class _ConnexionTabState extends State<_ConnexionTab> {
  final _formKey     = GlobalKey<FormState>();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();

  bool    _isLoading    = false;
  bool    _obscure      = true;
  String? _errorMessage;

  int    _lockSeconds = 0;
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
    _passCtrl.dispose();
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

    final result = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);

    final l = AppLocalizations.of(context);
    switch (result) {
      case AuthResult.success:
        Navigator.pop(context, true);
      case AuthResult.wrongCredentials:
        if (auth.isBlocked) {
          _startLockCountdown(auth.remainingLockDuration.inSeconds);
          setState(() => _errorMessage = null);
        } else {
          setState(() => _errorMessage = l.t('login_wrong_credentials'));
        }
      case AuthResult.tooManyAttempts:
        _startLockCountdown(auth.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      case AuthResult.invalidEmail:
        setState(() => _errorMessage = l.t('login_email_invalid'));
      default:
        setState(() => _errorMessage = l.t('login_error_network'));
    }
  }

  Future<void> _motDePasseOublie() async {
    final l = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ForgotPasswordSheet(controller: ctrl),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Bandeau info prestataire
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('login_reserved'),
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l.t('login_email_field'),
                prefixIcon: const Icon(Icons.email_outlined),
                hintText: l.t('login_email_hint'),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l.t('form_required');
                if (!_isValidEmail(v)) return l.t('login_email_invalid');
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: l.t('login_password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty)
                  ? l.t('form_required')
                  : null,
              onFieldSubmitted: (_) => _connexion(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _motDePasseOublie,
                child: Text(l.t('login_forgot_password')),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 4),
              _ErrorBanner(message: _errorMessage!),
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
                  : Text(l.t('login_button'),
                      style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// TAB INSCRIPTION — photo + nom/prénom + téléphone + email + mot de passe
// ==============================================================
class _InscriptionTab extends StatefulWidget {
  const _InscriptionTab();
  @override
  State<_InscriptionTab> createState() => _InscriptionTabState();
}

class _InscriptionTabState extends State<_InscriptionTab> {
  final _formKey     = GlobalKey<FormState>();
  final _prenomCtrl  = TextEditingController();
  final _nomCtrl     = TextEditingController();
  final _telCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _pass2Ctrl   = TextEditingController();

  bool    _isLoading    = false;
  bool    _obscure      = true;
  bool    _obscure2     = true;
  String? _errorMessage;
  XFile?  _photo;
  bool    _cguAcceptees = false;

  int    _lockSeconds = 0;
  Timer? _lockTimer;

  @override
  void dispose() {
    _lockTimer?.cancel();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
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

  Future<void> _pickPhoto(ImageSource source) async {
    final type = source == ImageSource.camera ? MediaType.camera : MediaType.photos;
    if (!await demanderPermissionMedia(context, type)) return;
    final img = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (img != null && mounted) setState(() => _photo = img);
  }

  String? _validatePhone(String? v) {
    final l = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) return l.t('form_required');
    if (!RegExp(r'^6\d{8}$').hasMatch(v.trim())) return l.t('login_phone_invalid');
    return null;
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
    setState(() { _isLoading = true; _errorMessage = null; });

    final auth = AuthService.instance;
    final result = await auth.register(
      email:     _emailCtrl.text.trim(),
      password:  _passCtrl.text,
      nom:       _nomCtrl.text.trim(),
      prenom:    _prenomCtrl.text.trim(),
      telephone: '+237${_telCtrl.text.trim()}',
    );

    if (!mounted) return;

    if (result != AuthResult.success) {
      setState(() => _isLoading = false);
      _handleError(result);
      return;
    }

    // Compte créé : upload de la photo (optionnelle, non bloquante).
    if (_photo != null && auth.currentUser != null) {
      try {
        final urls = await StorageService.uploadMultiplePhotos(
          uid:        auth.currentUser!.id,
          logementId: 'profile_${auth.currentUser!.id}',
          images:     [_photo!],
        );
        if (urls.isNotEmpty) {
          await auth.updatePhotoUrl(urls.first);
        }
      } catch (_) {
        // photo non bloquante
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Confirmation + rappel de vérification d'email, puis retour connecté.
    await showEmailVerificationDialog(context, _emailCtrl.text.trim());
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _handleError(AuthResult result) {
    final l = AppLocalizations.of(context);
    switch (result) {
      case AuthResult.emailAlreadyUsed:
        setState(() => _errorMessage = l.t('login_error_already_registered'));
      case AuthResult.invalidEmail:
        setState(() => _errorMessage = l.t('login_email_invalid'));
      case AuthResult.weakPassword:
        setState(() => _errorMessage = l.t('login_password_too_short'));
      case AuthResult.tooManyAttempts:
        _startLockCountdown(
            AuthService.instance.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      default:
        setState(() => _errorMessage = l.t('login_error_network_register'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('login_reserved'),
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ─── PHOTO ───────────────────────────────────────
            Center(
              child: Column(children: [
                GestureDetector(
                  onTap: () => _pickPhoto(ImageSource.gallery),
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: _photo != null
                        ? FileImage(File(_photo!.path))
                        : null,
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

            // ─── TÉLÉPHONE (contact, pas d'auth) ─────────────
            TextFormField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
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
              validator: _validatePhone,
            ),
            const SizedBox(height: 12),

            // ─── EMAIL ────────────────────────────────────────
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l.t('login_email_field'),
                prefixIcon: const Icon(Icons.email_outlined),
                hintText: l.t('login_email_hint'),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l.t('form_required');
                if (!_isValidEmail(v)) return l.t('login_email_invalid');
                return null;
              },
            ),
            const SizedBox(height: 4),
            Text(l.t('login_register_email_info'),
                style: AppTextStyles.caption
                    .copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 12),

            // ─── MOT DE PASSE ─────────────────────────────────
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: l.t('login_password_field'),
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: l.t('login_password_hint'),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? l.t('login_password_too_short')
                  : null,
            ),
            const SizedBox(height: 12),

            // ─── CONFIRMATION MOT DE PASSE ────────────────────
            TextFormField(
              controller: _pass2Ctrl,
              obscureText: _obscure2,
              decoration: InputDecoration(
                labelText: l.t('login_password_confirm'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure2 ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
              validator: (v) => (v != _passCtrl.text)
                  ? l.t('login_password_mismatch')
                  : null,
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_isLocked) ...[
              const SizedBox(height: 12),
              _LockBanner(seconds: _lockSeconds),
            ],
            const SizedBox(height: 16),

            // ─── CGU ──────────────────────────────────────────
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
                  : Text(l.t('login_register_cta'),
                      style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// FEUILLE « MOT DE PASSE OUBLIÉ »
// ==============================================================
class _ForgotPasswordSheet extends StatefulWidget {
  final TextEditingController controller;
  const _ForgotPasswordSheet({required this.controller});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  bool    _isLoading = false;
  String? _message;
  bool    _isError = false;

  Future<void> _envoyer() async {
    final l = AppLocalizations.of(context);
    final email = widget.controller.text.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() { _isError = true; _message = l.t('login_email_invalid'); });
      return;
    }
    setState(() { _isLoading = true; _message = null; });
    final result = await AuthService.instance.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result == AuthResult.success) {
        _isError = false;
        _message = '${l.t('login_forgot_sent')} $email. '
            '${l.t('login_forgot_check_spam')}';
      } else if (result == AuthResult.wrongCredentials) {
        _isError = true;
        _message = l.t('login_forgot_no_account');
      } else {
        _isError = true;
        _message = l.t('login_error_network');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('login_forgot_title'),
              style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
          const SizedBox(height: 8),
          Text(l.t('login_forgot_subtitle'),
              style: AppTextStyles.bodyMedium
                  .copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l.t('login_email_field'),
              prefixIcon: const Icon(Icons.email_outlined),
              hintText: l.t('login_email_hint'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            _isError
                ? _ErrorBanner(message: _message!)
                : _SuccessBanner(message: _message!),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _envoyer,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _isLoading
                ? const _Spinner()
                : Text(l.t('login_forgot_send')),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.t('login_close')),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================
// DIALOG DE VÉRIFICATION D'EMAIL
// Réutilisable : après inscription et depuis le profil.
// ==============================================================
Future<void> showEmailVerificationDialog(
    BuildContext context, String email) {
  final l = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EmailVerificationDialog(email: email, l: l),
  );
}

class _EmailVerificationDialog extends StatefulWidget {
  final String email;
  final AppLocalizations l;
  const _EmailVerificationDialog({required this.email, required this.l});

  @override
  State<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  bool _busy = false;

  Future<void> _renvoyer() async {
    setState(() => _busy = true);
    final result = await AuthService.instance.renvoyerEmailVerification();
    if (!mounted) return;
    setState(() => _busy = false);
    final l = widget.l;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result == AuthResult.success
          ? l.t('login_verify_resent')
          : l.t('login_error_network')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _jaiVerifie() async {
    setState(() => _busy = true);
    final ok = await AuthService.instance.reloadEmailVerifie();
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(widget.l.t('login_verify_ok')),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(widget.l.t('login_verify_not_yet')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.mark_email_unread_outlined, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(l.t('login_verify_email_title'))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('login_verify_email_intro')),
          const SizedBox(height: 4),
          Text(widget.email,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(l.t('login_verify_email_instr'),
              style: AppTextStyles.caption
                  .copyWith(color: context.appTextSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _renvoyer,
          child: Text(l.t('login_verify_resend')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.t('login_close')),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _jaiVerifie,
          child: _busy
              ? const _Spinner()
              : Text(l.t('login_verify_check')),
        ),
      ],
    );
  }
}

// ==============================================================
// BANNIÈRES & INDICATEURS PARTAGÉS
// ==============================================================

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

/// Bannière de succès verte.
class _SuccessBanner extends StatelessWidget {
  final String message;
  const _SuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final green = Colors.green.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.1),
        border: Border.all(color: green.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: green, fontSize: 13, height: 1.4),
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

/// Indicateur de chargement compact pour les boutons.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            color: Colors.white, strokeWidth: 2),
      );
}
