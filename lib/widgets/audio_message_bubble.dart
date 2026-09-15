// ============================================================
// FICHIER : lib/widgets/audio_message_bubble.dart
//
// Lecteur de note vocale dans une bulle de conversation.
// Bouton play/pause, barre de progression et compteur mm:ss.
// ============================================================
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AudioMessageBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  /// Duree en millisecondes memorisee au moment de l'envoi. Sert d'estimation
  /// tant que le fichier n'est pas charge, puis est remplacee par la duree
  /// reelle lue depuis le fichier.
  final int? initialDurationMs;

  const AudioMessageBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
    this.initialDurationMs,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    if (widget.initialDurationMs != null && widget.initialDurationMs! > 0) {
      _duration = Duration(milliseconds: widget.initialDurationMs!);
    }
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _durationSub = _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      // `resume` reprend au dernier `_position`, `play(UrlSource)` demarre.
      if (_position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.audioUrl));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lecture impossible : $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seekTo(double value) async {
    final total = _duration.inMilliseconds;
    if (total <= 0) return;
    final target = Duration(milliseconds: (total * value).round());
    await _player.seek(target);
    setState(() => _position = target);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final onDark = widget.isMe; // fond primary → texte/icones clairs
    final fg = onDark ? Colors.white : AppColors.primary;
    final trackColor = onDark
        ? Colors.white.withValues(alpha: 0.35)
        : AppColors.primary.withValues(alpha: 0.25);

    final total = _duration.inMilliseconds;
    final progress = total > 0
        ? (_position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: _loading ? null : _toggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: onDark
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: fg),
                    )
                  : Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: fg,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12),
                    activeTrackColor: fg,
                    inactiveTrackColor: trackColor,
                    thumbColor: fg,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: total > 0 ? _seekTo : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _playing || _position > Duration.zero
                        ? '${_fmt(_position)} / ${_fmt(_duration)}'
                        : _fmt(_duration),
                    style: TextStyle(
                      fontSize: 11,
                      color: onDark
                          ? Colors.white70
                          : AppColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
