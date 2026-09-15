// ============================================================
// FICHIER : lib/widgets/audio_recorder_button.dart
//
// Bouton microphone qui devient bouton envoyer lorsqu'un texte est saisi.
// A la pression prolongee (long press) sur le micro, il enregistre une
// note vocale et remonte le fichier + la duree au parent.
// ============================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';

/// Contrat de retour d'une note vocale enregistree.
typedef OnAudioRecorded = Future<void> Function(File file, Duration duration);

class RecordSendButton extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final OnAudioRecorded onAudioRecorded;
  final bool disabled;

  const RecordSendButton({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAudioRecorded,
    this.disabled = false,
  });

  @override
  State<RecordSendButton> createState() => _RecordSendButtonState();
}

class _RecordSendButtonState extends State<RecordSendButton> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _cancelled = false;
  DateTime? _startedAt;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    // On redessine le bouton (micro vs envoyer) au fur et a mesure de la saisie.
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  Future<bool> _ensurePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Micro requis pour enregistrer une note vocale.'),
        ));
      }
      return false;
    }
    return true;
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    if (!await _ensurePermission()) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(
        // AAC-LC 128k mono : format lu partout, poids raisonnable pour 30 s.
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Impossible de demarrer l'enregistrement : $e"),
        ));
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _cancelled = false;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _currentPath = path;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_isRecording || _startedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;
    _ticker?.cancel();
    _ticker = null;
    final elapsed = _elapsed;
    final path = _currentPath;
    setState(() {
      _isRecording = false;
      _startedAt = null;
      _elapsed = Duration.zero;
      _currentPath = null;
    });

    String? finalPath;
    try {
      finalPath = await _recorder.stop();
    } catch (_) {
      finalPath = null;
    }
    finalPath ??= path;

    if (!send || _cancelled || finalPath == null) {
      // On tente de nettoyer le fichier temporaire — inoffensif si absent.
      if (finalPath != null) {
        try {
          await File(finalPath).delete();
        } catch (_) {}
      }
      return;
    }

    // Trop courte (moins de 500 ms) : consideree comme un tap accidentel.
    if (elapsed < const Duration(milliseconds: 500)) {
      try {
        await File(finalPath).delete();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Maintenez le micro pour enregistrer une note vocale.'),
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    try {
      await widget.onAudioRecorded(File(finalPath), elapsed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur envoi note vocale : $e'),
        ));
      }
    }
  }

  void _cancelRecording() {
    _cancelled = true;
    _stopRecording(send: false);
  }

  String _fmtElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Mode saisie texte : bouton envoyer classique.
    if (_hasText && !_isRecording) {
      return GestureDetector(
        onTap: widget.disabled ? null : widget.onSend,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.disabled ? AppColors.textHint : AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send, color: Colors.white, size: 20),
        ),
      );
    }

    // Mode enregistrement : bouton devient rouge, le temps est affiche a cote.
    if (_isRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: _cancelRecording,
            icon: const Icon(Icons.close, size: 18, color: AppColors.error),
            label: const Text(
              'Annuler',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Text(
            _fmtElapsed(_elapsed),
            style: const TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _stopRecording(send: true),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      );
    }

    // Etat repos : microphone. Long press pour enregistrer.
    return GestureDetector(
      onLongPressStart: (_) {
        if (!widget.disabled) _startRecording();
      },
      onLongPressEnd: (_) => _stopRecording(send: true),
      onTap: () {
        // Un tap simple ne demarre pas l'enregistrement — on informe l'utilisateur.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Maintenez le micro pour enregistrer.'),
          duration: Duration(seconds: 2),
        ));
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: widget.disabled ? AppColors.textHint : AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 22),
      ),
    );
  }
}
