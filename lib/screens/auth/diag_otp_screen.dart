import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';

// ============================================================
// FICHIER : lib/screens/auth/diag_otp_screen.dart
// Écran debug uniquement — accessible par long-press caché sur le titre
// du login_screen. Affiche tout ce qu'il faut pour comprendre pourquoi
// l'OTP Firebase échoue (SHA absente, App Check KO, etc.).
// ============================================================

class DiagOtpScreen extends StatefulWidget {
  const DiagOtpScreen({super.key});

  @override
  State<DiagOtpScreen> createState() => _DiagOtpScreenState();
}

class _DiagOtpScreenState extends State<DiagOtpScreen> {
  /// `null` = chargement, `true` = token reçu, `false` = échec.
  bool? _appCheckOk;
  String? _appCheckError;

  @override
  void initState() {
    super.initState();
    _testAppCheck();
  }

  Future<void> _testAppCheck() async {
    setState(() {
      _appCheckOk = null;
      _appCheckError = null;
    });
    try {
      final token =
          await FirebaseAppCheck.instance.getToken(true);
      if (!mounted) return;
      setState(() => _appCheckOk = token != null && token.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appCheckOk = false;
        _appCheckError = e.toString();
      });
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).t('diag_otp_copied')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fb = Firebase.app().options;
    const packageName = 'com.horemplus.app';
    final diag = AuthService.lastOtpDiag;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l.t('diag_otp_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── FIREBASE CONFIG ──────────────────────────────
          _Section(title: l.t('diag_otp_firebase_section')),
          _DiagRow(
            label: l.t('diag_otp_project_id'),
            value: fb.projectId,
            onCopy: () => _copy(fb.projectId),
          ),
          _DiagRow(
            label: l.t('diag_otp_app_id'),
            value: fb.appId,
            onCopy: () => _copy(fb.appId),
          ),
          _DiagRow(
            label: l.t('diag_otp_package_name'),
            value: packageName,
            onCopy: () => _copy(packageName),
          ),

          const SizedBox(height: 20),

          // ─── APP CHECK ───────────────────────────────────
          _Section(title: l.t('diag_otp_appcheck_section')),
          _AppCheckStatus(
            ok: _appCheckOk,
            error: _appCheckError,
            onRetry: _testAppCheck,
          ),

          const SizedBox(height: 20),

          // ─── SHA ──────────────────────────────────────────
          _Section(title: l.t('diag_otp_sha_section')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(l.t('diag_otp_sha_info'),
                style: AppTextStyles.bodyMedium),
          ),
          _DiagRow(
            label: 'cmd',
            value: l.t('diag_otp_sha_command'),
            onCopy: () => _copy(l.t('diag_otp_sha_command')),
            monospace: true,
          ),

          const SizedBox(height: 20),

          // ─── DERNIÈRE ERREUR ─────────────────────────────
          _Section(title: l.t('diag_otp_last_error_section')),
          if (diag == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.t('diag_otp_no_error'),
                  style: AppTextStyles.bodyMedium),
            )
          else
            _LastErrorCard(diag: diag),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── COMPOSANTS PRIVÉS ────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool monospace;

  const _DiagRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E2D3D)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 14),
            label: Text(l.t('diag_otp_copy'),
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppCheckStatus extends StatelessWidget {
  final bool? ok;
  final String? error;
  final VoidCallback onRetry;

  const _AppCheckStatus({
    required this.ok,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final Color color;
    final IconData icon;
    final String label;
    if (ok == null) {
      color = Colors.orange.shade700;
      icon = Icons.hourglass_top;
      label = l.t('diag_otp_appcheck_loading');
    } else if (ok == true) {
      color = Colors.green.shade700;
      icon = Icons.check_circle_outline;
      label = l.t('diag_otp_appcheck_ok');
    } else {
      color = Colors.red.shade700;
      icon = Icons.error_outline;
      label = l.t('diag_otp_appcheck_ko');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style: TextStyle(
                    color: color, fontSize: 11, fontFamily: 'monospace')),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(l.t('diag_otp_recheck_appcheck'),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastErrorCard extends StatelessWidget {
  final OtpDiag diag;
  const _LastErrorCard({required this.diag});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t(diag.i18nReasonKey),
              style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 6),
          Text(l.t(diag.i18nHintKey),
              style: TextStyle(
                  color: Colors.red.shade700, fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          Text('code: ${diag.code}',
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace')),
          if (diag.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('msg: ${diag.message}',
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace')),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${l.t('diag_otp_at')} ${diag.at.toIso8601String()}',
                style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
