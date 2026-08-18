package com.horemplus.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /**
     * Enregistre les plugins écrits pour cette app.
     *
     * `SmsRetrieverPlugin` doit être ajouté explicitement : l'enregistrement
     * automatique de Flutter ne couvre que les plugins déclarés dans un
     * `pubspec.yaml` de package, pas le code natif du projet lui-même.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SmsRetrieverPlugin())
    }
}
