import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import 'auth/login_screen.dart';

// ============================================================
// FICHIER : lib/screens/profil_screen.dart
// Écran 7 - Profil / Paramètres (§4.1.7)
// Informations personnelles (prestataires), langue, mode,
// notifications, déconnexion, suppression de compte
// ============================================================

class ProfilScreen extends StatefulWidget {
  final bool isPrestataire;
  final Utilisateur? utilisateur;

  const ProfilScreen({super.key, this.isPrestataire = false, this.utilisateur});

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  // Préférences utilisateur
  bool _notifNouvellesAnnonces = true;
  bool _notifMessages = true;
  bool _notifAlertesPrix = false;
  String _langue = 'Français';
  bool _modeSombre = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil & Paramètres')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ─── EN-TÊTE PROFIL ─────────────────────────────────
            _EnteteProfil(
              utilisateur: widget.utilisateur,
              isPrestataire: widget.isPrestataire,
            ),

            const SizedBox(height: 16),

            // ─── BLOC CONNEXION (si non prestataire) ────────────
            if (!widget.isPrestataire)
              _Section(
                title: 'Compte prestataire',
                children: [
                  _OptionTile(
                    icon: Icons.home_work_outlined,
                    label: 'Publier un bien immobilier',
                    sublabel: 'Créez un compte prestataire gratuit',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(isInscription: true))),
                  ),
                  _OptionTile(
                    icon: Icons.login,
                    label: 'Se connecter',
                    sublabel: 'Déjà prestataire ? Connectez-vous',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  ),
                ],
              ),

            // ─── INFORMATIONS PERSONNELLES (prestataires) ───────
            if (widget.isPrestataire && widget.utilisateur != null)
              _Section(
                title: 'Mes informations',
                children: [
                  _InfoTile(label: 'Nom', value: widget.utilisateur!.nomComplet),
                  _InfoTile(label: 'Email', value: widget.utilisateur!.email),
                  _InfoTile(label: 'Téléphone', value: widget.utilisateur!.telephone),
                  _OptionTile(
                    icon: Icons.edit_outlined,
                    label: 'Modifier mes informations',
                    onTap: () => _modifierProfil(context),
                  ),
                ],
              ),

            // ─── LANGUE (§4.1.7 FR/EN) ──────────────────────────
            _Section(
              title: 'Langue / Language',
              children: [
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.language, color: AppColors.primary, size: 20),
                  ),
                  title: const Text('Langue', style: AppTextStyles.bodyLarge),
                  subtitle: Text(_langue, style: AppTextStyles.bodyMedium),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _choisirLangue(context),
                ),
              ],
            ),

            // ─── APPARENCE ───────────────────────────────────────
            _Section(
              title: 'Apparence',
              children: [
                SwitchListTile(
                  secondary: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: Icon(_modeSombre ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary, size: 20),
                  ),
                  title: const Text('Mode sombre', style: AppTextStyles.bodyLarge),
                  subtitle: Text(_modeSombre ? 'Activé' : 'Désactivé', style: AppTextStyles.bodyMedium),
                  value: _modeSombre,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() => _modeSombre = v);
                    AppController.instance.toggleTheme();
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),

            // ─── NOTIFICATIONS (§4.1.7 - par catégorie) ─────────
            _Section(
              title: 'Notifications',
              children: [
                SwitchListTile(
                  secondary: const _NotifIcon(icon: Icons.home_outlined),
                  title: const Text('Nouvelles annonces', style: AppTextStyles.bodyLarge),
                  subtitle: const Text('Alertes pour les biens correspondant à vos critères', style: TextStyle(fontSize: 12)),
                  value: _notifNouvellesAnnonces,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _notifNouvellesAnnonces = v),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                const Divider(indent: 68, height: 1),
                SwitchListTile(
                  secondary: const _NotifIcon(icon: Icons.chat_bubble_outline),
                  title: const Text('Messages', style: AppTextStyles.bodyLarge),
                  subtitle: const Text('Nouveaux messages de prestataires', style: TextStyle(fontSize: 12)),
                  value: _notifMessages,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _notifMessages = v),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                const Divider(indent: 68, height: 1),
                SwitchListTile(
                  secondary: const _NotifIcon(icon: Icons.trending_down),
                  title: const Text('Baisses de prix', style: AppTextStyles.bodyLarge),
                  subtitle: const Text('Alertes quand un bien favori baisse de prix', style: TextStyle(fontSize: 12)),
                  value: _notifAlertesPrix,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _notifAlertesPrix = v),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),

            // ─── À PROPOS ────────────────────────────────────────
            _Section(
              title: 'Informations',
              children: [
                _OptionTile(
                  icon: Icons.help_outline,
                  label: 'Aide & FAQ',
                  onTap: () {},
                ),
                _OptionTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Politique de confidentialité',
                  onTap: () {},
                ),
                _OptionTile(
                  icon: Icons.description_outlined,
                  label: 'Conditions d\'utilisation',
                  onTap: () {},
                ),
                _OptionTile(
                  icon: Icons.star_outline,
                  label: 'Évaluer l\'application',
                  onTap: () {},
                ),
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  ),
                  title: const Text('Version', style: AppTextStyles.bodyLarge),
                  trailing: const Text('1.0.0 MVP', style: AppTextStyles.caption),
                ),
              ],
            ),

            // ─── ACTIONS COMPTE ──────────────────────────────────
            if (widget.isPrestataire) ...[
              _Section(
                title: 'Compte',
                children: [
                  _OptionTile(
                    icon: Icons.logout,
                    label: 'Se déconnecter',
                    onTap: () => _confirmerDeconnexion(context),
                    color: AppColors.error,
                  ),
                  _OptionTile(
                    icon: Icons.delete_forever_outlined,
                    label: 'Supprimer mon compte',
                    sublabel: 'Action irréversible',
                    onTap: () => _confirmerSuppression(context),
                    color: AppColors.error,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _choisirLangue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Choisir la langue', style: AppTextStyles.h3)),
            const Divider(),
            ListTile(
              leading: const Text('🇫🇷', style: TextStyle(fontSize: 24)),
              title: const Text('Français'),
              trailing: _langue == 'Français' ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
              onTap: () {
                setState(() => _langue = 'Français');
                AppController.instance.setLocale(const Locale('fr'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
              title: const Text('English'),
              trailing: _langue == 'English' ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
              onTap: () {
                setState(() => _langue = 'English');
                AppController.instance.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _modifierProfil(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _ModificationProfilScreen()));
  }

  void _confirmerDeconnexion(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous devrez vous reconnecter pour accéder à votre espace prestataire.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
  }

  void _confirmerSuppression(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text('Toutes vos annonces seront supprimées définitivement. Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------
// EN-TÊTE PROFIL
// ----------------------------------------------------------
class _EnteteProfil extends StatelessWidget {
  final Utilisateur? utilisateur;
  final bool isPrestataire;

  const _EnteteProfil({this.utilisateur, required this.isPrestataire});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: utilisateur?.photoUrl != null
                ? null
                : Text(
              utilisateur?.prenom[0] ?? '?',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            utilisateur != null ? utilisateur!.nomComplet : 'Visiteur',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (utilisateur != null)
            Text(utilisateur!.email, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          if (isPrestataire)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (utilisateur?.estVerifie == true)
                  _Badge(label: '✓ Vérifié', bg: Colors.white, fg: AppColors.primary),
                const SizedBox(width: 8),
                if (utilisateur?.estPremium == true)
                  _Badge(label: '★ Premium', bg: AppColors.accent, fg: Colors.black),
              ],
            )
          else
            const _Badge(label: 'Mode visiteur · Sans compte', bg: Colors.white24, fg: Colors.white),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

// ----------------------------------------------------------
// SECTION PARAMÈTRES
// ----------------------------------------------------------
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
        ),
        Container(
          color: Theme.of(context).cardTheme.color,
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// TUILE OPTION NAVIGABLE
// ----------------------------------------------------------
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback onTap;
  final Color? color;

  const _OptionTile({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color ?? AppColors.primary, size: 20),
    ),
    title: Text(label, style: AppTextStyles.bodyLarge.copyWith(color: color)),
    subtitle: sublabel != null ? Text(sublabel!, style: const TextStyle(fontSize: 12)) : null,
    trailing: Icon(Icons.arrow_forward_ios, size: 14, color: color ?? AppColors.textHint),
    onTap: onTap,
  );
}

// ----------------------------------------------------------
// TUILE INFO (non cliquable)
// ----------------------------------------------------------
class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label, style: AppTextStyles.bodyMedium),
    trailing: Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500)),
  );
}

// ----------------------------------------------------------
// ICÔNE NOTIFICATION
// ----------------------------------------------------------
class _NotifIcon extends StatelessWidget {
  final IconData icon;
  const _NotifIcon({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
    child: Icon(icon, color: AppColors.primary, size: 20),
  );
}

// ----------------------------------------------------------
// ÉCRAN MODIFICATION PROFIL
// ----------------------------------------------------------
class _ModificationProfilScreen extends StatelessWidget {
  const _ModificationProfilScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            TextFormField(decoration: const InputDecoration(labelText: 'Prénom', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextFormField(decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextFormField(decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextFormField(decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined), hintText: '+237 6XX XXX XXX'), keyboardType: TextInputType.phone),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}