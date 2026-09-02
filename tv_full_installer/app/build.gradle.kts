plugins {
    id("com.android.application")
}

android {
    namespace = "com.tvfull.pro.installer"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.tvfull.pro.installer"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            val storePath = System.getenv("TV_FULL_INSTALLER_KEYSTORE")
            if (!storePath.isNullOrBlank()) {
                storeFile = file(storePath)
                storePassword = System.getenv("TV_FULL_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TV_FULL_KEY_ALIAS")
                keyPassword = System.getenv("TV_FULL_KEY_PASSWORD")
            }
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = false
            enableV4Signing = false
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
