plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.moran.retrostation"
    compileSdk = flutter.compileSdkVersion
    // NDK fijado: es el que compila los núcleos C++ (mGBA) desde la Etapa 2.
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.moran.retrostation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 7.0+: es el mínimo de Flutter 3.50 y de url_launcher_android.
        // El audio usa AAudio en Android 8.0+ y OpenSL ES en 7.x.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                // El núcleo se compila optimizado incluso en debug: sin -O2 un
                // emulador no alcanza la velocidad original.
                arguments += listOf("-DCMAKE_BUILD_TYPE=Release")
                cFlags += listOf("-O2")
                cppFlags += listOf("-O2")
            }
        }
    }

    // Frontend libretro (C++) y núcleos de emulación: ver native/CMakeLists.txt
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.31.6"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
