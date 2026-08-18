package com.horemplus.app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import android.util.Log
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException

/**
 * Calcule le hash à 11 caractères qui identifie l'app auprès de la SMS
 * Retriever API de Google.
 *
 * Ce hash DOIT terminer le SMS d'OTP, sinon Android reçoit bien le message
 * mais ne le transmet jamais à l'app : l'autofill ne se déclenche pas et
 * l'utilisateur doit recopier le code à la main.
 *
 * ⚠️ Le hash dépend de la clé de signature. Il change donc entre le build de
 * debug, le build signé avec android/key.properties, et le build re-signé par
 * Google Play (Play App Signing). C'est pour cette raison que l'app calcule le
 * hash à l'exécution et l'envoie au backend à chaque demande de code, au lieu
 * de le figer côté serveur.
 *
 * Algorithme officiel (developers.google.com/identity/sms-retriever/verify) :
 *   SHA-256( "<package> <signature-hex>" ) → base64 → 11 premiers caractères.
 */
object AppSignatureHelper {

    private const val TAG = "AppSignatureHelper"
    private const val HASH_TYPE = "SHA-256"
    private const val NUM_HASHED_BYTES = 9
    private const val NUM_BASE64_CHAR = 11

    /**
     * Retourne les hashes de toutes les signatures de l'app.
     * Une app n'en a normalement qu'une ; la liste couvre les cas de rotation
     * de clé (Play App Signing en cours de migration).
     */
    fun signatures(context: Context): List<String> {
        val resultats = mutableListOf<String>()
        try {
            val packageName = context.packageName
            val pm = context.packageManager

            val signaturesBrutes: Array<out android.content.pm.Signature> =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val info = pm.getPackageInfo(
                        packageName,
                        PackageManager.GET_SIGNING_CERTIFICATES,
                    )
                    val signing = info.signingInfo
                    when {
                        signing == null -> emptyArray()
                        signing.hasMultipleSigners() -> signing.apkContentsSigners
                        else -> signing.signingCertificateHistory
                    }
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
                        ?: emptyArray()
                }

            for (signature in signaturesBrutes) {
                val hash = hash(packageName, signature.toCharsString())
                if (hash != null) resultats.add(hash)
            }
        } catch (e: Exception) {
            // Non fatal : sans hash, le backend enverra un SMS classique et
            // l'utilisateur saisira le code lui-même.
            Log.w(TAG, "Calcul du hash de signature impossible : ${e.message}")
        }
        return resultats
    }

    private fun hash(packageName: String, signature: String): String? {
        val donnees = "$packageName $signature"
        return try {
            val md = MessageDigest.getInstance(HASH_TYPE)
            md.update(donnees.toByteArray(StandardCharsets.UTF_8))
            val empreinte = md.digest().copyOfRange(0, NUM_HASHED_BYTES)
            Base64.encodeToString(empreinte, Base64.NO_PADDING or Base64.NO_WRAP)
                .substring(0, NUM_BASE64_CHAR)
        } catch (e: NoSuchAlgorithmException) {
            Log.w(TAG, "SHA-256 indisponible : ${e.message}")
            null
        }
    }
}
