import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/paiement_debug_log.dart';

// ============================================================
// FICHIER : lib/widgets/silent_payment_webview.dart
//
// WebView monté mais INVISIBLE, utilisé pour déclencher l'USSD push
// PawaPay sans que l'utilisateur voie la page GeniusPay.
//
// Principe :
//   Le WebView charge checkoutUrl → exécute le JavaScript de la page
//   → la page contacte PawaPay → PawaPay envoie l'USSD au téléphone.
//   Le menu PIN Mobile Money s'ouvre directement sur l'écran du client.
//
// Rendu :
//   - IgnorePointer : ne capte aucun tap.
//   - Opacity 0     : totalement transparent.
//   - SizedBox 1x1  : ne prend qu'un pixel (mais MONTÉ, donc le JS tourne).
//
// On ne peut pas utiliser Offstage(offstage: true) car Flutter peut alors
// arrêter d'exécuter les frames du WebView.
// ============================================================

class SilentPaymentWebView extends StatefulWidget {
  final String url;
  final VoidCallback? onLoaded;

  const SilentPaymentWebView({
    super.key,
    required this.url,
    this.onLoaded,
  });

  @override
  State<SilentPaymentWebView> createState() => _SilentPaymentWebViewState();
}

class _SilentPaymentWebViewState extends State<SilentPaymentWebView> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final log = PaiementDebugLog.instance;
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) => log.info('WebView invisible → $url'),
            onPageFinished: (url) {
              log.ok('WebView invisible : page chargée ($url)');
              widget.onLoaded?.call();
            },
            onWebResourceError: (e) => log.warn(
              'WebView erreur : ${e.description} (${e.errorType})',
            ),
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
      _controller = controller;
    } catch (e) {
      log.err('WebView init impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: c),
        ),
      ),
    );
  }
}
