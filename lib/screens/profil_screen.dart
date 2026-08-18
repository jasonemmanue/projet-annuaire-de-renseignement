import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/shared_widgets.dart' as sw;
import 'auth/login_screen.dart';
import 'aide_faq_screen.dart';
import 'legal/cgu_screen.dart';
import 'legal/politique_screen.dart';

// ============================================================
// FICHIER : lib/screens/profil_screen.dart
// Écran 7 - Profil / Paramètres (§4.1.7)
// Informations personnelles (prestataires), langue, mode,
// notifications, déconnexion, suppression de compte
// ============================================================

class ProfilScreen extends StatefulWidget {
  final bool isPrestataire;
  final Utilisateur? utilisateur;
  final VoidCallback? onPrestataireAcces;

  const ProfilScreen({
    super.key,
    this.isPrestataire = false,
    this.utilisateur,
    this.onPrestataireAcces,
  });

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  bool _notifNouvellesAnnonces = true;
  bool _notifMessages = true;
  bool _notifAlertesPrix = false;
  late String _langue;
  late bool _modeSombre;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _modeSombre = AppController.instance.isDark;
    _langue = AppController.instance.locale.languageCode == 'en'
        ? 'English'
        : 'Français';
    _chargerPrefsNotifs();
    _chargerVersion();
  }

  Future<void> _chargerVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _chargerPrefsNotifs() async {
    final prefs = await NotificationService.loadAllPreferences();
    if (!mounted) return;
    setState(() {
      _notifNouvellesAnnonces = prefs[NotificationService.kNotifAnnonces]!;
      _notifMessages          = prefs[NotificationService.kNotifMessages]!;
      _notifAlertesPrix       = prefs[NotificationService.kNotifPrix]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l.t('profil_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: sw.SkylineBackground(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 8, left: 16, right: 16, bottom: 40),
          child: Column(
            children: [
              _EnteteProfil(
                utilisateur: widget.utilisateur,
                isPrestataire: widget.isPrestataire,
              ),

              if (widget.isPrestataire &&
                  widget.utilisateur != null &&
                  AuthService.instance.currentUser?.compteGratuit != true &&
                  !AuthService.instance.isEmailVerified) ...[
                const SizedBox(height: 12),
                _EmailNonVerifieBanner(
                  email: AuthService.instance.currentEmail ??
                      widget.utilisateur?.email ??
                      '',
                  onChanged: () => setState(() {}),
                ),
              ],

              const SizedBox(height: 12),

              if (!widget.isPrestataire)
                _Section(
                  title: l.t('profil_prestataire_account'),
                  children: [
                    _OptionTile(
                      icon: Icons.home_work_outlined,
                      label: l.t('profil_publish'),
                      sublabel: l.t('profil_publish_sub'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(isInscription: true))),
                    ),
                    _OptionTile(
                      icon: Icons.login,
                      label: l.t('profil_login'),
                      sublabel: l.t('profil_login_sub'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                    ),
                  ],
                ),

              if (widget.isPrestataire && widget.utilisateur != null)
                _Section(
                  title: l.t('profil_my_info'),
                  children: [
                    _InfoTile(label: 'Nom', value: widget.utilisateur!.nomComplet),
                    _InfoTile(label: 'Email', value: widget.utilisateur?.email ?? ''),
                    _InfoTile(label: 'Téléphone', value: widget.utilisateur!.telephone),
                    _OptionTile(
                      icon: Icons.edit_outlined,
                      label: l.t('profil_edit'),
                      onTap: () => _modifierProfil(context),
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              _Section(
                title: l.t('profil_language_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.language, color: AppColors.primary, size: 20),
                    ),
                    title: Text(l.t('profil_language'), style: AppTextStyles.bodyLarge),
                    subtitle: Text(_langue, style: AppTextStyles.bodyMedium),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => _choisirLangue(context),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _Section(
                title: l.t('profil_appearance'),
                children: [
                  SwitchListTile(
                    secondary: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
                      child: Icon(_modeSombre ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary, size: 20),
                    ),
                    title: Text(l.t('profil_dark_mode'), style: AppTextStyles.bodyLarge),
                    subtitle: Text(
                      _modeSombre ? l.t('profil_enabled') : l.t('profil_disabled'),
                      style: AppTextStyles.bodyMedium,
                    ),
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

              const SizedBox(height: 12),

              _Section(
                title: l.t('profil_notifs'),
                children: [
                  SwitchListTile(
                    secondary: const _NotifIcon(icon: Icons.home_outlined),
                    title: Text(l.t('profil_new_listings'), style: AppTextStyles.bodyLarge),
                    subtitle: Text(l.t('profil_new_listings_sub'), style: const TextStyle(fontSize: 12)),
                    value: _notifNouvellesAnnonces,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) async {
                      setState(() => _notifNouvellesAnnonces = v);
                      await NotificationService.setCategory(
                          NotificationService.kNotifAnnonces, v);
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  const Divider(indent: 68, height: 1),
                  SwitchListTile(
                    secondary: const _NotifIcon(icon: Icons.chat_bubble_outline),
                    title: Text(l.t('profil_messages_notif'), style: AppTextStyles.bodyLarge),
                    subtitle: Text(l.t('profil_messages_notif_sub'), style: const TextStyle(fontSize: 12)),
                    value: _notifMessages,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) async {
                      setState(() => _notifMessages = v);
                      await NotificationService.setCategory(
                          NotificationService.kNotifMessages, v);
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  const Divider(indent: 68, height: 1),
                  SwitchListTile(
                    secondary: const _NotifIcon(icon: Icons.trending_down),
                    title: Text(l.t('profil_price_alerts'), style: AppTextStyles.bodyLarge),
                    subtitle: Text(l.t('profil_price_alerts_sub'), style: const TextStyle(fontSize: 12)),
                    value: _notifAlertesPrix,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) async {
                      setState(() => _notifAlertesPrix = v);
                      await NotificationService.setCategory(
                          NotificationService.kNotifPrix, v);
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _Section(
                title: l.t('profil_info_section'),
                children: [
                  _OptionTile(
                    icon: Icons.help_outline,
                    label: l.t('profil_help'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AideFaqScreen())),
                  ),
                  _OptionTile(
                    icon: Icons.privacy_tip_outlined,
                    label: l.t('profil_privacy'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PolitiqueScreen())),
                  ),
                  _OptionTile(
                    icon: Icons.description_outlined,
                    label: l.t('profil_terms'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CguScreen())),
                  ),
                  _OptionTile(
                    icon: Icons.star_outline,
                    label: l.t('profil_rate'),
                    onTap: () => _ouvrirStoreListing(context),
                  ),
                  ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                    ),
                    title: Text(l.t('profil_version_label'), style: AppTextStyles.bodyLarge),
                    trailing: Text(_version.isEmpty ? '…' : _version, style: AppTextStyles.caption),
                  ),
                ],
              ),

              if (widget.isPrestataire) ...[
                const SizedBox(height: 12),
                _Section(
                  title: l.t('profil_account_section'),
                  children: [
                    _OptionTile(
                      icon: Icons.logout,
                      label: l.t('profil_logout'),
                      onTap: () => _confirmerDeconnexion(context),
                      color: AppColors.error,
                    ),
                    _OptionTile(
                      icon: Icons.delete_forever_outlined,
                      label: l.t('profil_delete_account'),
                      sublabel: l.t('profil_delete_sub'),
                      onTap: () => _confirmerSuppression(context),
                      color: AppColors.error,
                    ),
                  ],
                ),
              ],

              if (!widget.isPrestataire && widget.onPrestataireAcces != null) ...[
                const SizedBox(height: 16),
                Column(
                  children: [
                    Text(
                      l.t('profil_prestataire_question'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: widget.onPrestataireAcces,
                      icon: const Icon(Icons.business_center_outlined),
                      label: Text(l.t('prestataire_access')),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              Text('Horem+ v${_version.isEmpty ? '…' : _version}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ouvrirStoreListing(BuildContext context) async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.openStoreListing(appStoreId: 'com.horemplus.app');
    } else {
      final uri = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.horemplus.app');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _choisirLangue(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(l.t('profil_choose_language'), style: AppTextStyles.h3)),
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
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.t('profil_logout_confirm_title')),
        content: Text(l.t('profil_logout_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.t('common_cancel'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l.t('profil_logout_action')),
          ),
        ],
      ),
    );
  }

  void _confirmerSuppression(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.t('profil_delete_confirm_title')),
        content: Text(l.t('profil_delete_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.t('common_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l.t('profil_delete_confirm_action')),
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
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.88);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: utilisateur?.photoUrl != null
                ? null
                : Text(
              utilisateur?.prenom[0] ?? '?',
              style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            utilisateur != null ? utilisateur!.nomComplet : AppLocalizations.of(context).t('profil_visitor'),
            style: TextStyle(color: context.appTextPrimary, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (utilisateur != null)
            Text(utilisateur?.email ?? '', style: TextStyle(color: context.appTextSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          if (isPrestataire)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (utilisateur?.estVerifie == true)
                  const _Badge(label: '✓ Vérifié', bg: AppColors.success, fg: Colors.white),
                const SizedBox(width: 8),
                if (utilisateur?.estPremium == true)
                  _Badge(label: '★ Premium', bg: Colors.amber.shade600, fg: Colors.white),
              ],
            )
          else
            _Badge(label: AppLocalizations.of(context).t('profil_visitor_badge'), bg: AppColors.primary, fg: Colors.white),
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
    final cardColor = Theme.of(context).cardColor.withValues(alpha: 0.88);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
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
    decoration: BoxDecoration(color: context.appPrimaryLight, borderRadius: BorderRadius.circular(8)),
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('profil_edit_title'))),
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
              child: Text(l.t('common_save')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bannière orange affichée aux prestataires dont l'email n'est pas vérifié.
/// Ouvre le dialog de vérification (renvoi du lien + rafraîchissement).
class _EmailNonVerifieBanner extends StatelessWidget {
  final String email;
  final VoidCallback onChanged;
  const _EmailNonVerifieBanner({required this.email, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await showEmailVerificationDialog(context, email);
          onChanged();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.mark_email_unread_outlined,
                  color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('login_verify_banner'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.t('login_verify_resend'),
                      style: TextStyle(
                          fontSize: 12, color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.warning),
            ],
          ),
        ),
      ),
    );
  }
}