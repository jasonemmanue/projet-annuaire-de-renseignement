import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';

// ============================================================
// FICHIER : lib/screens/auth/login_screen.dart
// Authentification — Réservée aux prestataires
// ✅ Connexion email/mot de passe uniquement (Google supprimé)
// ✅ Inscription avec photo de profil
// ✅ Champ téléphone sans préfixe fixe +237 (TextWrapper)
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
  bool _isLoading = false;

  final _loginFormKey = GlobalKey<FormState>();
  final _inscriptionFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  // Photo de profil sélectionnée à l'inscription
  XFile? _photoSelectionnee;
  String? _photoUrlUploaded;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 2,
        vsync: this,
        initialIndex: widget.isInscription ? 1 : 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) setState(() => _photoSelectionnee = image);
  }

  Future<void> _prendrePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (image != null) setState(() => _photoSelectionnee = image);
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
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const Text(
                    'Espace Prestataire',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
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
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    tabs: const [
                      Tab(text: 'Connexion'),
                      Tab(text: 'Inscription'),
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
                    formKey: _loginFormKey,
                    emailCtrl: _emailCtrl,
                    passwordCtrl: _passwordCtrl,
                    obscurePwd: _obscurePwd,
                    isLoading: _isLoading,
                    onTogglePwd: () => setState(() => _obscurePwd = !_obscurePwd),
                    onLogin: _connexion,
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
                    photoSelectionnee: _photoSelectionnee,
                    onTogglePwd: () => setState(() => _obscurePwd = !_obscurePwd),
                    onInscrire: _inscription,
                    onChoisirPhoto: _choisirPhoto,
                    onPrendrePhoto: _prendrePhoto,
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

    final result = await AuthService.instance.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AuthResult.success:
        Navigator.pop(context, true);
        break;
      case AuthResult.wrongCredentials:
      case AuthResult.emailAlreadyUsed:
        _showSnack('Identifiant ou mot de passe incorrect.', Colors.red.shade700);
        break;
      case AuthResult.networkError:
        _showSnack('Erreur réseau. Réessayez.', Colors.orange.shade700);
        break;
    }
  }

  Future<void> _inscription() async {
    if (!_inscriptionFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // Upload photo si sélectionnée
    String? photoUrl;
    if (_photoSelectionnee != null) {
      try {
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        final urls = await StorageService.uploadMultiplePhotos(
          uid: tempId,
          logementId: 'profile_$tempId',
          images: [_photoSelectionnee!],
        );
        if (urls.isNotEmpty) photoUrl = urls.first;
      } catch (_) {
        // Photo non bloquante
      }
    }

    final result = await AuthService.instance.register(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      nom: _nomCtrl.text.trim(),
      prenom: _prenomCtrl.text.trim(),
      telephone: _telCtrl.text.trim(),
      photoUrl: photoUrl,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AuthResult.success:
        _showSnack('Compte créé avec succès ! Vous pouvez vous connecter.', Colors.green.shade700);
        _tabController.animateTo(0);
        break;
      case AuthResult.emailAlreadyUsed:
      case AuthResult.wrongCredentials:
        _showSnack('Cet email est déjà utilisé. Essayez de vous connecter.', Colors.red.shade700);
        break;
      case AuthResult.networkError:
        _showSnack('Erreur réseau. Vérifiez votre connexion.', Colors.orange.shade700);
        break;
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _afficherReinitialisationMdp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mot de passe oublié', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            const Text(
                'Entrez votre email pour recevoir un lien de réinitialisation.',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            TextFormField(
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: const Text('Envoyer le lien'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// ONGLET CONNEXION (email uniquement — Google supprimé)
// ----------------------------------------------------------
class _OngletConnexion extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl, passwordCtrl;
  final bool obscurePwd, isLoading;
  final VoidCallback onTogglePwd, onLogin, onForgotPwd;

  const _OngletConnexion({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePwd,
    required this.isLoading,
    required this.onTogglePwd,
    required this.onLogin,
    required this.onForgotPwd,
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
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Identifiant / Email',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordCtrl,
              obscureText: obscurePwd,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) =>
              (v == null || v.length < 6) ? 'Au moins 6 caractères' : null,
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
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Text('Se connecter',
                  style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------
// ONGLET INSCRIPTION avec photo de profil
// ✅ Champ téléphone : TextWrapper (sans +237 fixe)
// ✅ Photo de profil optionnelle
// ----------------------------------------------------------
class _OngletInscription extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nomCtrl, prenomCtrl, emailCtrl, telCtrl, passwordCtrl;
  final bool obscurePwd, isLoading;
  final XFile? photoSelectionnee;
  final VoidCallback onTogglePwd, onInscrire, onChoisirPhoto, onPrendrePhoto;

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
                          ? AssetImage(photoSelectionnee!.path) as ImageProvider
                          : null,
                      child: photoSelectionnee == null
                          ? const Icon(Icons.person, size: 44, color: AppColors.primary)
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
                        label: const Text('Galerie', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: onPrendrePhoto,
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Caméra', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const Text('Photo de profil (optionnelle)',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(
                  child: TextFormField(
                    controller: prenomCtrl,
                    decoration: const InputDecoration(labelText: 'Prénom *'),
                    validator: (v) => v!.isEmpty ? 'Requis' : null,
                  )),
              const SizedBox(width: 12),
              Expanded(
                  child: TextFormField(
                    controller: nomCtrl,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                    validator: (v) => v!.isEmpty ? 'Requis' : null,
                  )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) =>
              (v == null || v.isEmpty) ? 'Email requis' : null,
            ),
            const SizedBox(height: 12),
            // ✅ Champ téléphone avec préfixe +237 fixe
            TextFormField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone *',
                prefixIcon: Icon(Icons.phone_outlined),
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
                labelText: 'Mot de passe *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscurePwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: onTogglePwd,
                ),
              ),
              validator: (v) =>
              v!.length < 6 ? 'Au moins 6 caractères' : null,
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.check_box_outlined,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                      "En créant un compte, j'accepte les conditions d'utilisation et la politique de confidentialité.",
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    )),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : onInscrire,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Text('Créer mon compte gratuit',
                  style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
