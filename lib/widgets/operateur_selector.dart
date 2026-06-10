import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

// ============================================================
// FICHIER : lib/widgets/operateur_selector.dart
// Sélection de l'opérateur Mobile Money (Cameroun) + saisie du
// numéro avec préfixe +237 pré-affiché (l'utilisateur tape juste
// les 9 chiffres : 6XX XX XX XX).
//
// Images des opérateurs : prises en ligne (logos officiels) avec
// repli stylé si le réseau échoue.
//
// Callback : onChanged(operateur, telephoneComplet)
//   operateur        : 'orange' | 'mtn' | null
//   telephoneComplet : '+237XXXXXXXXX' ou null si invalide
// ============================================================

class OperateurSelector extends StatefulWidget {
  /// Appelé à chaque changement : (operateur, telephoneComplet|null).
  final void Function(String? operateur, String? telephoneComplet) onChanged;

  /// Numéro pré-rempli éventuel (format libre, sera nettoyé).
  final String? telephoneInitial;

  const OperateurSelector({
    super.key,
    required this.onChanged,
    this.telephoneInitial,
  });

  @override
  State<OperateurSelector> createState() => _OperateurSelectorState();
}

class _OperateurSelectorState extends State<OperateurSelector> {
  final _ctrl = TextEditingController();
  String? _operateur; // 'orange' | 'mtn'

  // Logos opérateurs.
  static const _logoOrange = 'assets/images/operateurs/orange.svg';
  static const _logoMtn = 'assets/images/operateurs/mtn.svg';

  @override
  void initState() {
    super.initState();
    final local = _numeroLocal(widget.telephoneInitial ?? '');
    if (local != null) _ctrl.text = local;
    _ctrl.addListener(_notifier);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Extrait les 9 chiffres locaux camerounais (6XXXXXXXX) ou null.
  String? _numeroLocal(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('237')) d = d.substring(3);
    if (RegExp(r'^6\d{8}$').hasMatch(d)) return d;
    return null;
  }

  void _notifier() {
    final local = _numeroLocal(_ctrl.text);
    final complet = local != null ? '+237$local' : null;
    widget.onChanged(_operateur, _operateur != null ? complet : null);
    setState(() {}); // rafraîchit l'état du bouton/validation
  }

  void _choisir(String op) {
    setState(() => _operateur = op);
    _notifier();
  }

  @override
  Widget build(BuildContext context) {
    final local = _numeroLocal(_ctrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choisissez votre opérateur',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _carteOperateur(
              code: 'orange',
              nom: 'Orange Money',
              logoAsset: _logoOrange,
              couleur: Colors.deepOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _carteOperateur(
              code: 'mtn',
              nom: 'MTN MoMo',
              logoAsset: _logoMtn,
              couleur: const Color(0xFFFFCC00),
              fgFallback: Colors.black87,
            ),
          ),
        ]),
        const SizedBox(height: 18),
        const Text('Votre numéro',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: InputDecoration(
            prefixText: '+237  ',
            prefixStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
            hintText: '6 XX XX XX XX',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            suffixIcon: local != null
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : null,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Le préfixe +237 est ajouté automatiquement.',
            style: TextStyle(fontSize: 12, color: AppColors.textHint)),
      ],
    );
  }

  Widget _carteOperateur({
    required String code,
    required String nom,
    required String logoAsset,
    required Color couleur,
    Color? fgFallback,
  }) {
    final selected = _operateur == code;
    return GestureDetector(
      onTap: () => _choisir(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? couleur.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? couleur : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: SvgPicture.asset(
                logoAsset,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: couleur,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    code == 'mtn' ? 'MTN' : 'O',
                    style: TextStyle(
                        color: fgFallback ?? Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(nom,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? couleur : Colors.black87)),
            if (selected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, color: couleur, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
