import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

// ============================================================
// ÉCRAN : AideFaqScreen — Aide & FAQ + Contact support
// ============================================================

const _kSupportEmail    = 'horemplus@gmail.com';
const _kSupportWhatsApp = '237695236917';

class AideFaqScreen extends StatelessWidget {
  const AideFaqScreen({super.key});

  Future<void> _openEmail(BuildContext ctx) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _kSupportEmail,
      queryParameters: {'subject': 'Support Horem+'},
    );
    if (!await launchUrl(uri)) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la messagerie.')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext ctx) async {
    final uri = Uri.parse('https://wa.me/$_kSupportWhatsApp');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final questions = [
      (l.t('aide_q1'), l.t('aide_a1')),
      (l.t('aide_q2'), l.t('aide_a2')),
      (l.t('aide_q3'), l.t('aide_a3')),
      (l.t('aide_q4'), l.t('aide_a4')),
      (l.t('aide_q5'), l.t('aide_a5')),
      (l.t('aide_q6'), l.t('aide_a6')),
      (l.t('aide_q7'), l.t('aide_a7')),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.t('aide_title'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── FAQ ──────────────────────────────────────────────
          ...questions.map((qa) => _FaqTile(question: qa.$1, answer: qa.$2)),

          const SizedBox(height: 16),
          const Divider(),

          // ── Contact support ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l.t('aide_contact_section').toUpperCase(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _ContactBtn(
                  icon: Icons.email_outlined,
                  label: l.t('aide_email_btn'),
                  sublabel: _kSupportEmail,
                  color: AppColors.primary,
                  onTap: () => _openEmail(context),
                ),
                const SizedBox(height: 12),
                _ContactBtn(
                  icon: Icons.chat_outlined,
                  label: l.t('aide_whatsapp_btn'),
                  sublabel: '+$_kSupportWhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _openWhatsApp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(question,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.textHint,
      children: [
        Text(answer,
            style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 13,
                height: 1.5)),
      ],
    );
  }
}

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;
  const _ContactBtn({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(sublabel,
                    style: TextStyle(
                        color: color.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
