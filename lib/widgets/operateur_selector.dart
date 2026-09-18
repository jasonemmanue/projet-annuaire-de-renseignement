import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

// ============================================================
// FICHIER : lib/widgets/operateur_selector.dart
// Sélection du pays (Cameroun / Côte d'Ivoire) + opérateur Mobile
// Money, puis saisie du numéro avec préfixe pays pré-affiché.
//
// Codes retournés dans le callback `onChanged(operateur, telephone)` :
//   Cameroun         → 'orange_cm' | 'mtn_cm'
//   Côte d'Ivoire    → 'orange_ci' | 'mtn_ci' | 'moov_ci' | 'wave_ci'
//   telephoneComplet → '+237XXXXXXXXX' (CM) ou '+225XXXXXXXXXX' (CI)
//
// Le callback `onCountryChanged(pays)` est optionnel : il permet
// aux écrans de paiement de passer `pays` à la Cloud Function
// (`'CM'` ou `'CI'`), pour que GeniusPay route vers le bon
// provider PawaPay.
// ============================================================

/// Alias ISO pays supportés.
enum PaysPaiement {
  cameroun, // 'CM' — préfixe +237, 9 chiffres commençant par 6
  coteIvoire, // 'CI' — préfixe +225, 10 chiffres commençant par 0
}

extension PaysPaiementX on PaysPaiement {
  String get iso {
    switch (this) {
      case PaysPaiement.cameroun:
        return 'CM';
      case PaysPaiement.coteIvoire:
        return 'CI';
    }
  }

  String get indicatif {
    switch (this) {
      case PaysPaiement.cameroun:
        return '+237';
      case PaysPaiement.coteIvoire:
        return '+225';
    }
  }

  String get nom {
    switch (this) {
      case PaysPaiement.cameroun:
        return '🇨🇲 Cameroun';
      case PaysPaiement.coteIvoire:
        return '🇨🇮 Côte d\'Ivoire';
    }
  }
}

class OperateurSelector extends StatefulWidget {
  /// Appelé à chaque changement : (operateur, telephoneComplet|null).
  ///
  /// Codes opérateur retournés :
  ///   'orange_cm' | 'mtn_cm' (Cameroun) ·
  ///   'orange_ci' | 'mtn_ci' | 'moov_ci' | 'wave_ci' (Côte d'Ivoire).
  final void Function(String? operateur, String? telephoneComplet) onChanged;

  /// Optionnel : notifie le pays choisi ('CM' | 'CI').
  final void Function(String pays)? onCountryChanged;

  /// Numéro pré-rempli éventuel (format libre, sera nettoyé).
  final String? telephoneInitial;

  /// Pays par défaut à afficher (Cameroun si non précisé).
  final PaysPaiement paysInitial;

  const OperateurSelector({
    super.key,
    required this.onChanged,
    this.onCountryChanged,
    this.telephoneInitial,
    this.paysInitial = PaysPaiement.cameroun,
  });

  @override
  State<OperateurSelector> createState() => _OperateurSelectorState();
}

class _OperateurSelectorState extends State<OperateurSelector> {
  final _ctrl = TextEditingController();
  late PaysPaiement _pays;
  String? _operateur; // ex : 'orange_cm', 'wave_ci'

  // Logos opérateurs.
  static const _logoOrange = 'assets/images/operateurs/orange.svg';
  static const _logoMtn = 'assets/images/operateurs/mtn.svg';
  static const _logoMoov = 'assets/images/operateurs/moov.svg';
  static const _logoWave = 'assets/images/operateurs/wave.svg';

  @override
  void initState() {
    super.initState();
    _pays = widget.paysInitial;
    final local = _numeroLocal(widget.telephoneInitial ?? '');
    if (local != null) _ctrl.text = local;
    _ctrl.addListener(_notifier);
    // Prévenir immédiatement du pays initial pour que les écrans
    // qui écoutent aient la bonne valeur dès le premier build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onCountryChanged?.call(_pays.iso);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Extrait le numéro local selon le pays choisi (sans indicatif),
  /// ou null si le format ne colle pas.
  ///   CM : 9 chiffres, commence par 6.
  ///   CI : 10 chiffres, commence par 0.
  String? _numeroLocal(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    switch (_pays) {
      case PaysPaiement.cameroun:
        if (d.startsWith('237')) d = d.substring(3);
        return RegExp(r'^6\d{8}$').hasMatch(d) ? d : null;
      case PaysPaiement.coteIvoire:
        if (d.startsWith('225')) d = d.substring(3);
        return RegExp(r'^0\d{9}$').hasMatch(d) ? d : null;
    }
  }

  /// Longueur maximum du champ selon le pays.
  int get _maxLen => _pays == PaysPaiement.cameroun ? 9 : 10;

  /// Placeholder de saisie selon le pays.
  String get _hint =>
      _pays == PaysPaiement.cameroun ? '6 XX XX XX XX' : '07 XX XX XX XX';

  void _notifier() {
    final local = _numeroLocal(_ctrl.text);
    final complet = local != null ? '${_pays.indicatif}$local' : null;
    widget.onChanged(_operateur, _operateur != null ? complet : null);
    if (mounted) setState(() {});
  }

  void _choisir(String op) {
    setState(() => _operateur = op);
    _notifier();
  }

  void _changerPays(PaysPaiement pays) {
    if (pays == _pays) return;
    setState(() {
      _pays = pays;
      _operateur = null; // le code d'opérateur porte le pays
      _ctrl.clear();
    });
    widget.onCountryChanged?.call(pays.iso);
    _notifier();
  }

  @override
  Widget build(BuildContext context) {
    final local = _numeroLocal(_ctrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paysToggle(),
        const SizedBox(height: 16),
        const Text('Choisissez votre opérateur',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _grilleOperateurs(),
        const SizedBox(height: 18),
        const Text('Votre numéro',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maxLen),
          ],
          decoration: InputDecoration(
            prefixText: '${_pays.indicatif}  ',
            prefixStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
            hintText: _hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            suffixIcon: local != null
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : null,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        Text('Le préfixe ${_pays.indicatif} est ajouté automatiquement.',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
      ],
    );
  }

  Widget _paysToggle() {
    return Row(children: [
      Expanded(child: _pastillePays(PaysPaiement.cameroun)),
      const SizedBox(width: 10),
      Expanded(child: _pastillePays(PaysPaiement.coteIvoire)),
    ]);
  }

  Widget _pastillePays(PaysPaiement pays) {
    final selected = _pays == pays;
    return GestureDetector(
      onTap: () => _changerPays(pays),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(pays.nom,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : Colors.black87)),
          ],
        ),
      ),
    );
  }

  /// Grille d'opérateurs adaptée au pays courant.
  Widget _grilleOperateurs() {
    final ops = _pays == PaysPaiement.cameroun
        ? const [
            _Op('orange_cm', 'Orange Money', _logoOrange, Colors.deepOrange,
                fgFallback: Colors.white),
            _Op('mtn_cm', 'MTN MoMo', _logoMtn, Color(0xFFFFCC00),
                fgFallback: Colors.black87),
          ]
        : const [
            _Op('orange_ci', 'Orange Money', _logoOrange, Colors.deepOrange,
                fgFallback: Colors.white),
            _Op('mtn_ci', 'MTN MoMo', _logoMtn, Color(0xFFFFCC00),
                fgFallback: Colors.black87),
            _Op('moov_ci', 'Moov Money', _logoMoov, Color(0xFF0071BC),
                fgFallback: Colors.white),
            _Op('wave_ci', 'Wave', _logoWave, Color(0xFF1DC0F5),
                fgFallback: Colors.white),
          ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final op in ops)
          SizedBox(
            width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
            child: _carteOperateur(op: op),
          ),
      ],
    );
  }

  Widget _carteOperateur({required _Op op}) {
    final selected = _operateur == op.code;
    return GestureDetector(
      onTap: () => _choisir(op.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? op.couleur.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? op.couleur : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: SvgPicture.asset(
                op.logo,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => _logoRepli(op),
              ),
            ),
            const SizedBox(height: 8),
            Text(op.nom,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? op.couleur : Colors.black87)),
            if (selected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, color: op.couleur, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  /// Repli si l'asset SVG est absent — évite un crash `SvgAssetLoader`
  /// « unable to load asset » sur les nouveaux opérateurs (moov, wave)
  /// avant que les logos soient ajoutés dans le dossier assets.
  Widget _logoRepli(_Op op) {
    String label;
    switch (op.code) {
      case 'orange_cm':
      case 'orange_ci':
        label = 'O';
        break;
      case 'mtn_cm':
      case 'mtn_ci':
        label = 'MTN';
        break;
      case 'moov_ci':
        label = 'MOOV';
        break;
      case 'wave_ci':
        label = 'W';
        break;
      default:
        label = op.nom.characters.first;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: op.couleur,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            color: op.fgFallback ?? Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: label.length > 2 ? 11 : 14),
      ),
    );
  }
}

class _Op {
  final String code;
  final String nom;
  final String logo;
  final Color couleur;
  final Color? fgFallback;
  const _Op(this.code, this.nom, this.logo, this.couleur, {this.fgFallback});
}
