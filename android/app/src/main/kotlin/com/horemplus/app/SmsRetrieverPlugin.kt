package com.horemplus.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Pont Flutter ↔ SMS Retriever API (Google Play Services).
 *
 * Permet de lire automatiquement le code OTP du SMS **sans demander la
 * permission READ_SMS** : Play Services ne transmet à l'app que le seul message
 * qui se termine par le hash de sa propre signature. C'est l'écart décisif avec
 * les plugins de lecture de SMS, qui exigent une permission sensible que Google
 * Play refuse à une app immobilière.
 *
 * Canaux exposés :
 *   • MethodChannel `horemplus/sms_retriever`
 *       - `signatureApp()` → String? : hash à 11 caractères à joindre à la
 *          demande d'OTP pour que le backend formate le SMS correctement.
 *       - `demarrer()`     → Bool   : arme l'écoute (fenêtre de 5 minutes).
 *       - `arreter()`      → null   : désarme.
 *   • EventChannel `horemplus/sms_retriever/events`
 *       - émet le code à 6 chiffres extrait du SMS ;
 *       - émet une erreur `timeout` si la fenêtre de 5 minutes expire.
 *
 * iOS n'a pas d'équivalent : l'autofill y est natif (`textContentType
 * .oneTimeCode`), géré côté Flutter par `autofillHints`.
 */
class SmsRetrieverPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "SmsRetrieverPlugin"
        private const val CANAL_METHODES = "horemplus/sms_retriever"
        private const val CANAL_EVENEMENTS = "horemplus/sms_retriever/events"

        /** Extrait la première suite de 6 chiffres du corps du SMS. */
        private val REGEX_CODE = Regex("\\b(\\d{6})\\b")
    }

    private var contexte: Context? = null
    private var canalMethodes: MethodChannel? = null
    private var canalEvenements: EventChannel? = null
    private var emetteur: EventChannel.EventSink? = null
    private var recepteur: BroadcastReceiver? = null

    // ─── Cycle de vie du plugin ─────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        contexte = binding.applicationContext
        canalMethodes = MethodChannel(binding.binaryMessenger, CANAL_METHODES).also {
            it.setMethodCallHandler(this)
        }
        canalEvenements = EventChannel(binding.binaryMessenger, CANAL_EVENEMENTS).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        desenregistrerRecepteur()
        canalMethodes?.setMethodCallHandler(null)
        canalEvenements?.setStreamHandler(null)
        canalMethodes = null
        canalEvenements = null
        contexte = null
    }

    // ─── MethodChannel ──────────────────────────────────────────────────────

    override fun onMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val ctx = contexte
        if (ctx == null) {
            result.error("no_context", "Plugin non attaché", null)
            return
        }

        when (call.method) {
            "signatureApp" -> result.success(AppSignatureHelper.signatures(ctx).firstOrNull())

            "demarrer" -> {
                enregistrerRecepteur(ctx)
                SmsRetriever.getClient(ctx).startSmsRetriever()
                    .addOnSuccessListener {
                        Log.d(TAG, "SMS Retriever armé (fenêtre 5 min)")
                        result.success(true)
                    }
                    .addOnFailureListener { e ->
                        // Cas réel sur les appareils sans Google Play Services
                        // (certaines ROM Huawei) : on renvoie false et l'app
                        // bascule sur la saisie manuelle sans planter.
                        Log.w(TAG, "SMS Retriever indisponible : ${e.message}")
                        desenregistrerRecepteur()
                        result.success(false)
                    }
            }

            "arreter" -> {
                desenregistrerRecepteur()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ─── EventChannel ───────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        emetteur = events
    }

    override fun onCancel(arguments: Any?) {
        emetteur = null
        desenregistrerRecepteur()
    }

    // ─── BroadcastReceiver ──────────────────────────────────────────────────

    private fun enregistrerRecepteur(ctx: Context) {
        if (recepteur != null) return

        recepteur = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return

                val extras = intent.extras ?: return
                val statut = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return

                when (statut.statusCode) {
                    CommonStatusCodes.SUCCESS -> {
                        val message = extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE).orEmpty()
                        val code = REGEX_CODE.find(message)?.groupValues?.get(1)
                        if (code != null) {
                            Log.d(TAG, "Code OTP extrait automatiquement du SMS")
                            emetteur?.success(code)
                        } else {
                            // Le SMS portait bien notre hash mais pas de code à
                            // 6 chiffres : format backend modifié sans que le
                            // client soit à jour. Silencieux côté UI.
                            Log.w(TAG, "SMS reçu sans code à 6 chiffres identifiable")
                        }
                    }

                    CommonStatusCodes.TIMEOUT -> {
                        Log.d(TAG, "Fenêtre SMS Retriever expirée (5 min)")
                        emetteur?.error("timeout", "Aucun SMS reçu dans les 5 minutes", null)
                    }
                }
                // Fenêtre à usage unique : Play Services ne rediffusera rien.
                desenregistrerRecepteur()
            }
        }

        val filtre = IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION)
        // À partir d'Android 13, tout receveur dynamique doit déclarer s'il est
        // exporté. Le broadcast vient de Play Services (un autre processus) :
        // sans RECEIVER_EXPORTED, le système lève une SecurityException au
        // moment de l'enregistrement et l'app se ferme.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(recepteur, filtre, SmsRetriever.SEND_PERMISSION, null, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            ctx.registerReceiver(recepteur, filtre, SmsRetriever.SEND_PERMISSION, null)
        }
    }

    private fun desenregistrerRecepteur() {
        val r = recepteur ?: return
        try {
            contexte?.unregisterReceiver(r)
        } catch (e: IllegalArgumentException) {
            // Déjà désenregistré (double appel `arreter()` / détachement).
            Log.d(TAG, "Récepteur déjà retiré")
        }
        recepteur = null
    }
}
