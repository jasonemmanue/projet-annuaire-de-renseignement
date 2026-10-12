// ============================================================
// FICHIER : lib/screens/cni_screen.dart
//
// Carte nationale d'identité du prestataire (obligatoire pour publier).
//   • CniChamps : numéro + photos recto/verso (caméra ou galerie), réutilisé
//     dans le formulaire d'inscription ;
//   • CniScreen : dépôt pour un compte existant (ouvert quand l'API répond
//     « cni_requise » à la publication, ou depuis le profil).
// Les photos vont dans Firebase Storage (cni/<uid>/), l'API ne garde que les
// adresses et ne les montre qu'au titulaire et à l'admin.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/photo_source.dart';

/// Envoie la CNI (photos + numéro) pour l'utilisateur connecté.
Future<void> envoyerCni({
  required String uid,
  required String numero,
  required XFile recto,
  required XFile verso,
}) async {
  final urlRecto = await StorageService.uploadCni(uid: uid, face: 'recto', image: recto);
  final urlVerso = await StorageService.uploadCni(uid: uid, face: 'verso', image: verso);
  await ApiClient.instance.put('/users/me', {
    'cniNumero': numero.trim(),
    'cniRecto': urlRecto,
    'cniVerso': urlVerso,
  });
}

/// Champs CNI contrôlés par le parent.
class CniChamps extends StatelessWidget {
  final TextEditingController numeroCtrl;
  final XFile? recto;
  final XFile? verso;
  final ValueChanged<XFile> onRecto;
  final ValueChanged<XFile> onVerso;

  const CniChamps({
    super.key,
    required this.numeroCtrl,
    required this.recto,
    required this.verso,
    required this.onRecto,
    required this.onVerso,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: numeroCtrl,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: l.t('cni_number'),
          prefixIcon: const Icon(Icons.badge_outlined),
        ),
        validator: (v) => (v == null || v.trim().length < 5) ? l.t('cni_number_invalid') : null,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _FacePhoto(label: l.t('cni_front'), image: recto, onPick: onRecto)),
        const SizedBox(width: 10),
        Expanded(child: _FacePhoto(label: l.t('cni_back'), image: verso, onPick: onVerso)),
      ]),
      const SizedBox(height: 6),
      Text(l.t('cni_privacy'), style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
    ]);
  }
}

class _FacePhoto extends StatelessWidget {
  final String label;
  final XFile? image;
  final ValueChanged<XFile> onPick;
  const _FacePhoto({required this.label, required this.image, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final img = await choisirPhoto(context);
        if (img != null) onPick(img);
      },
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: image == null ? AppColors.border : AppColors.success),
        ),
        clipBehavior: Clip.antiAlias,
        child: image == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ])
            : Stack(fit: StackFit.expand, children: [
                Image.file(File(image!.path), fit: BoxFit.cover),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(label, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ]),
      ),
    );
  }
}

/// Dépôt de la CNI pour un compte existant. Renvoie true si envoyée.
class CniScreen extends StatefulWidget {
  const CniScreen({super.key});

  static Future<bool> ouvrir(BuildContext context) async =>
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CniScreen())) ==
      true;

  @override
  State<CniScreen> createState() => _CniScreenState();
}

class _CniScreenState extends State<CniScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numero = TextEditingController();
  XFile? _recto;
  XFile? _verso;
  bool _envoi = false;

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_recto == null || _verso == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('cni_photos_required'))));
      return;
    }
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;
    setState(() => _envoi = true);
    try {
      await envoyerCni(uid: uid, numero: _numero.text, recto: _recto!, verso: _verso!);
      await AuthService.instance.refreshCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t('cni_sent')), backgroundColor: AppColors.success));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('cni_title'))),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(l.t('cni_intro'), style: TextStyle(color: context.appTextSecondary, height: 1.4)),
          const SizedBox(height: 20),
          CniChamps(
            numeroCtrl: _numero,
            recto: _recto,
            verso: _verso,
            onRecto: (f) => setState(() => _recto = f),
            onVerso: (f) => setState(() => _verso = f),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _envoi ? null : _envoyer,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: _envoi
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(l.t('cni_submit')),
          ),
        ]),
      ),
    );
  }
}
