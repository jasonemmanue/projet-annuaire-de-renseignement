import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';

// ============================================================
// FICHIER : lib/screens/auth/login_screen.dart
// ✅ Authentification par OTP SMS (Firebase Phone Auth)
// ✅ Flux 2 étapes : numéro +237 → code à 6 chiffres
// ✅ Anti-brute-force conservé sur les échecs OTP
// ✅ Compte à rebours renvoi SMS (60 s)
// ✅ Auto-vérification Android transparente
// ✅ Inscription : collecte nom/prénom/photo avant OTP
// ============================================================

enum _Etape { telephone, otp }

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
      backgroundColor: AppColors.background,
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
                  Text(
                    l.t('login_space'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
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
                  _OtpConnexionTab(),
                  _OtpInscriptionTab(),
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
// TAB CONNEXION
// Étape 1 : numéro → Étape 2 : code OTP
// ==============================================================
class _OtpConnexionTab extends StatefulWidget {
  const _OtpConnexionTab();
  @override
  State<_OtpConnexionTab> createState() => _OtpConnexionTabState();
}

class _OtpConnexionTabState extends State<_OtpConnexionTab> {
  _Etape _etape = _Etape.telephone;

  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey   = GlobalKey<FormState>();
  final _telCtrl      = TextEditingController();
  final _otpCtrl      = TextEditingController();

  String  _verificationId = '';
  bool    _isLoading      = false;
  String? _errorMessage;

  int    _lockSeconds   = 0;
  Timer? _lockTimer;
  int    _resendSeconds = 0;
  Timer? _resendTimer;

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
    _resendTimer?.cancel();
    _telCtrl.dispose();
    _otpCtrl.dispose();
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

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (--_resendSeconds <= 0) { t.cancel(); _resendSeconds = 0; } });
    });
  }

  String get _fullPhone => '+225${_telCtrl.text.trim()}';

  Future<void> _envoyerCode() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await auth.envoyerOtp(
        telephone: _fullPhone,
        onCodeSent: (vid) {
          if (!mounted) return;
          setState(() {
            _verificationId = vid;
            _etape          = _Etape.otp;
            _isLoading      = false;
          });
          _startResendCountdown();
        },
        onError: (e) {
          if (!mounted) return;
          setState(() { _isLoading = false; _errorMessage = _smsError(e); });
        },
        onAutoVerified: (credential) async {
          if (!mounted) return;
          setState(() => _isLoading = true);
          final result = await auth.signInWithPhoneCredential(credential);
          if (!mounted) return;
          setState(() => _isLoading = false);
          _handleResult(result);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Erreur inattendue : $e'; });
    }
  }

  Future<void> _verifierCode() async {
    if (!_otpFormKey.currentState!.validate()) return;
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    final result = await auth.verifierOtp(
      verificationId: _verificationId,
      smsCode: _otpCtrl.text.trim(),
    );
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
        final auth = AuthService.instance;
        if (auth.isBlocked) {
          _startLockCountdown(auth.remainingLockDuration.inSeconds);
          setState(() => _errorMessage = null);
        } else {
          setState(() => _errorMessage = l.t('login_otp_invalid'));
        }
      case AuthResult.otpExpired:
        setState(() => _errorMessage = l.t('login_otp_expired'));
      case AuthResult.tooManyAttempts:
        _startLockCountdown(AuthService.instance.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      case AuthResult.networkError:
        setState(() => _errorMessage = l.t('login_error_network'));
      case AuthResult.emailAlreadyUsed:
        break;
    }
  }

  String _smsError(FirebaseAuthException e) {
    final l = AppLocalizations.of(context);
    return (e.code == 'invalid-phone-number' || e.code == 'missing-phone-number')
        ? l.t('login_phone_invalid')
        : l.t('login_sms_error');
  }

  String? _validatePhone(String? v) {
    final l = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) return l.t('form_required');
    if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) return l.t('login_phone_invalid');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _etape == _Etape.telephone
        ? _buildPhone(context)
        : _buildOtp(context);
  }

  Widget _buildPhone(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _phoneFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(l.t('login_phone_enter'), style: AppTextStyles.h3),
            const SizedBox(height: 12),
            // Bandeau info prestataire
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
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
            TextFormField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: l.t('login_phone'),
                prefixIcon: const Icon(Icons.phone_outlined),
                prefixText: '+225 ',
                hintText: l.t('login_phone_hint_otp'),
              ),
              validator: _validatePhone,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_isLocked) ...[
              const SizedBox(height: 12),
              _LockBanner(seconds: _lockSeconds),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_isLoading || _isLocked) ? null : _envoyerCode,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const _Spinner()
                  : Text(l.t('login_send_code'),
                      style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtp(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _otpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(l.t('login_otp_title'), style: AppTextStyles.h3),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                children: [
                  TextSpan(text: l.t('login_otp_sent_to')),
                  TextSpan(
                    text: '+225 ${_telCtrl.text.trim()}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(l.t('login_otp_enter'),
                style: AppTextStyles.caption),
            const SizedBox(height: 20),
            _OtpField(controller: _otpCtrl),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_isLocked) ...[
              const SizedBox(height: 12),
              _LockBanner(seconds: _lockSeconds),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_isLoading || _isLocked) ? null : _verifierCode,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const _Spinner()
                  : Text(l.t('login_verify_code'),
                      style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Center(
              child: _resendSeconds > 0
                  ? Text(
                      '${l.t('login_otp_resend_in')} ${_resendSeconds}s',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    )
                  : TextButton(
                      onPressed: _isLoading ? null : _envoyerCode,
                      child: Text(l.t('login_otp_resend')),
                    ),
            ),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _etape        = _Etape.telephone;
                  _errorMessage = null;
                  _otpCtrl.clear();
                  _resendTimer?.cancel();
                  _resendSeconds = 0;
                }),
                child: Text(
                  l.t('login_otp_change_number'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// TAB INSCRIPTION
// Étape 1 : nom/prénom/photo + numéro → Étape 2 : code OTP
// ==============================================================
class _OtpInscriptionTab extends StatefulWidget {
  const _OtpInscriptionTab();
  @override
  State<_OtpInscriptionTab> createState() => _OtpInscriptionTabState();
}

class _OtpInscriptionTabState extends State<_OtpInscriptionTab> {
  _Etape _etape = _Etape.telephone;

  final _step1FormKey = GlobalKey<FormState>();
  final _otpFormKey   = GlobalKey<FormState>();
  final _prenomCtrl   = TextEditingController();
  final _nomCtrl      = TextEditingController();
  final _telCtrl      = TextEditingController();
  final _otpCtrl      = TextEditingController();

  String  _verificationId = '';
  bool    _isLoading      = false;
  String? _errorMessage;
  XFile?  _photo;

  int    _lockSeconds   = 0;
  Timer? _lockTimer;
  int    _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _lockTimer?.cancel();
    _resendTimer?.cancel();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _otpCtrl.dispose();
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

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { if (--_resendSeconds <= 0) { t.cancel(); _resendSeconds = 0; } });
    });
  }

  String get _fullPhone => '+225${_telCtrl.text.trim()}';

  Future<void> _pickPhoto(ImageSource source) async {
    final img = await ImagePicker().pickImage(
        source: source, imageQuality: 80);
    if (img != null && mounted) setState(() => _photo = img);
  }

  String? _validatePhone(String? v) {
    final l = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) return l.t('form_required');
    if (!RegExp(r'^\d{10}$').hasMatch(v.trim())) return l.t('login_phone_invalid');
    return null;
  }

  Future<void> _envoyerCode() async {
    if (!_step1FormKey.currentState!.validate()) return;
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await auth.envoyerOtp(
        telephone: _fullPhone,
        onCodeSent: (vid) {
          if (!mounted) return;
          setState(() {
            _verificationId = vid;
            _etape          = _Etape.otp;
            _isLoading      = false;
          });
          _startResendCountdown();
        },
        onError: (e) {
          if (!mounted) return;
          final l = AppLocalizations.of(context);
          setState(() {
            _isLoading    = false;
            _errorMessage = (e.code == 'invalid-phone-number' ||
                    e.code == 'missing-phone-number')
                ? l.t('login_phone_invalid')
                : l.t('login_sms_error');
          });
        },
        onAutoVerified: (credential) async {
          if (!mounted) return;
          setState(() => _isLoading = true);
          final result = await auth.signInWithPhoneCredential(credential);
          if (!mounted) return;
          if (result == AuthResult.success) {
            await _completeProfile();
          } else {
            setState(() => _isLoading = false);
            _handleResult(result);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Erreur inattendue : $e'; });
    }
  }

  Future<void> _verifierCode() async {
    if (!_otpFormKey.currentState!.validate()) return;
    final auth = AuthService.instance;
    if (auth.isBlocked) {
      _startLockCountdown(auth.remainingLockDuration.inSeconds);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });

    final result = await auth.verifierOtp(
      verificationId: _verificationId,
      smsCode: _otpCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result == AuthResult.success) {
      await _completeProfile();
    } else {
      setState(() => _isLoading = false);
      _handleResult(result);
    }
  }

  Future<void> _completeProfile() async {
    final auth = AuthService.instance;
    String? photoUrl;
    if (_photo != null && auth.currentUser != null) {
      try {
        final urls = await StorageService.uploadMultiplePhotos(
          uid:        auth.currentUser!.id,
          logementId: 'profile_${auth.currentUser!.id}',
          images:     [_photo!],
        );
        if (urls.isNotEmpty) photoUrl = urls.first;
      } catch (_) {
        // photo non bloquante
      }
    }
    await auth.updateProfile(
      nom:      _nomCtrl.text.trim(),
      prenom:   _prenomCtrl.text.trim(),
      photoUrl: photoUrl,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(AppLocalizations.of(context).t('login_register_complete')),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
    Navigator.pop(context, true);
  }

  void _handleResult(AuthResult result) {
    final l = AppLocalizations.of(context);
    switch (result) {
      case AuthResult.wrongCredentials:
        final auth = AuthService.instance;
        if (auth.isBlocked) {
          _startLockCountdown(auth.remainingLockDuration.inSeconds);
          setState(() => _errorMessage = null);
        } else {
          setState(() => _errorMessage = l.t('login_otp_invalid'));
        }
      case AuthResult.otpExpired:
        setState(() => _errorMessage = l.t('login_otp_expired'));
      case AuthResult.tooManyAttempts:
        _startLockCountdown(
            AuthService.instance.remainingLockDuration.inSeconds);
        setState(() => _errorMessage = null);
      case AuthResult.networkError:
        setState(() => _errorMessage = l.t('login_error_network'));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _etape == _Etape.telephone
        ? _buildStep1(context)
        : _buildStep2(context);
  }

  Widget _buildStep1(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _step1FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
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
                        ? AssetImage(_photo!.path) as ImageProvider
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
                    style: AppTextStyles.caption),
              ]),
            ),
            const SizedBox(height: 16),

            // ─── NOM / PRÉNOM ────────────────────────────────
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _prenomCtrl,
                  decoration: InputDecoration(
                      labelText: l.t('login_firstname')),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? l.t('form_required')
                          : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _nomCtrl,
                  decoration:
                      InputDecoration(labelText: l.t('login_lastname')),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? l.t('form_required')
                          : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // ─── TÉLÉPHONE ────────────────────────────────────
            TextFormField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: l.t('login_phone'),
                prefixIcon: const Icon(Icons.phone_outlined),
                prefixText: '+225 ',
                hintText: l.t('login_phone_hint_otp'),
              ),
              validator: _validatePhone,
            ),
            const SizedBox(height: 6),
            Text(l.t('login_register_otp_info'),
                style: AppTextStyles.caption),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_isLocked) ...[
              const SizedBox(height: 12),
              _LockBanner(seconds: _lockSeconds),
            ],
            const SizedBox(height: 16),

            Row(children: [
              const Icon(Icons.check_box_outlined,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.t('login_terms'),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ]),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: (_isLoading || _isLocked) ? null : _envoyerCode,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const _Spinner()
                  : Text(l.t('login_send_code'),
                      style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _otpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(l.t('login_otp_title'), style: AppTextStyles.h3),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                children: [
                  TextSpan(text: l.t('login_otp_sent_to')),
                  TextSpan(
                    text: '+225 ${_telCtrl.text.trim()}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(l.t('login_otp_enter'), style: AppTextStyles.caption),
            const SizedBox(height: 20),
            _OtpField(controller: _otpCtrl),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_isLocked) ...[
              const SizedBox(height: 12),
              _LockBanner(seconds: _lockSeconds),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_isLoading || _isLocked) ? null : _verifierCode,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isLoading
                  ? const _Spinner()
                  : Text(l.t('login_verify_code'),
                      style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Center(
              child: _resendSeconds > 0
                  ? Text(
                      '${l.t('login_otp_resend_in')} ${_resendSeconds}s',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    )
                  : TextButton(
                      onPressed: _isLoading ? null : _envoyerCode,
                      child: Text(l.t('login_otp_resend')),
                    ),
            ),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _etape        = _Etape.telephone;
                  _errorMessage = null;
                  _otpCtrl.clear();
                  _resendTimer?.cancel();
                  _resendSeconds = 0;
                }),
                child: Text(
                  l.t('login_otp_change_number'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================
// WIDGETS UTILITAIRES PRIVÉS
// ==============================================================

/// Saisie OTP — 6 cases carrées à coins arrondis.
class _OtpField extends StatefulWidget {
  final TextEditingController controller;
  const _OtpField({required this.controller});

  @override
  State<_OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<_OtpField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});
  void _onFocus() => setState(() => _focused = _focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (i) {
                final filled = i < code.length;
                final active = _focused && i == code.length;
                return Container(
                  width: 46,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E2D3D)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active
                          ? AppColors.primary
                          : filled
                              ? AppColors.primary.withValues(alpha: 0.6)
                              : AppColors.primary.withValues(alpha: 0.25),
                      width: active ? 2.0 : 1.5,
                    ),
                    boxShadow: active
                        ? [BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )]
                        : null,
                  ),
                  child: Center(
                    child: filled
                        ? Text(
                            code[i],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          )
                        : active
                            ? Container(
                                width: 1.5,
                                height: 22,
                                color: AppColors.primary,
                              )
                            : null,
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  maxLength: 6,
                  validator: (v) => (v == null || v.length != 6)
                      ? AppLocalizations.of(context).t('login_otp_invalid')
                      : null,
                  autofocus: true,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bannière d'erreur rouge (code invalide, expiré, réseau).
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  height: 1.4),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              '${l.t('login_locked_prefix')}\n$retry',
              style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                  height: 1.4),
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
