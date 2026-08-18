import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de release : lue depuis android/key.properties, qui n'est PAS
// versionné (.gitignore). Voir android/key.properties.example pour le modèle.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        // PowerShell (Set-Content -Encoding UTF8) prefixe le fichier d'un BOM
        // que Properties.load() agrege a la premiere cle : `storePassword`
        // devient introuvable alors que le fichier parait correct a l'oeil.
        // On le retire avant lecture.
        load(keystorePropertiesFile.readText(Charsets.UTF_8).removePrefix("\uFEFF").reader())
    }
}

android {
    namespace = "com.horemplus.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true     // ← AJOUT
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.horemplus.app"
        minSdk = maxOf(flutter.minSdkVersion, 23)                             // ← valeur fixe au lieu de flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // Une propriete absente laisserait le champ a null, et l'echec ne
                // surviendrait qu'a la tache signReleaseBundle — apres tout le
                // build — sous la forme d'un NullPointerException sans message.
                // On echoue donc ici, avec le nom de la cle fautive.
                fun requis(cle: String): String =
                    keystoreProperties.getProperty(cle)
                        ?: throw GradleException(
                            "android/key.properties : propriete « $cle » absente ou vide. " +
                            "Les quatre cles attendues sont storePassword, keyPassword, " +
                            "keyAlias et storeFile (voir key.properties.example)."
                        )

                keyAlias = requis("keyAlias")
                keyPassword = requis("keyPassword")
                storePassword = requis("storePassword")

                val chemin = requis("storeFile")
                val fichier = file(chemin)
                if (!fichier.exists()) {
                    throw GradleException(
                        "Keystore introuvable : $chemin\n" +
                        "Verifiez storeFile dans android/key.properties. Le chemin doit " +
                        "utiliser des barres obliques (C:/Users/...), l'antislash etant " +
                        "un caractere d'echappement dans un fichier .properties."
                    )
                }
                storeFile = fichier
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Repli sur la clé de débogage pour ne pas bloquer un `flutter run
                // --release` local, mais Google Play REFUSE un artefact signé ainsi.
                logger.warn(
                    "\n⚠️  android/key.properties introuvable — le build release est " +
                    "signé avec la clé de DÉBOGAGE.\n" +
                    "   Google Play rejettera cet AAB. Voir android/key.properties.example.\n"
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")  // ← AJOUT

    // SMS Retriever API — autofill du code OTP sans permission READ_SMS.
    // Play Services ne transmet à l'app que le SMS terminé par le hash de sa
    // propre signature ; c'est ce qui permet de se passer d'une permission
    // sensible que Google Play refuserait à une app immobilière.
    implementation("com.google.android.gms:play-services-auth-api-phone:18.2.0")
}

flutter {
    source = "../.."
}
