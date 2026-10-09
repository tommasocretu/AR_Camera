plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "MarkerARPlugin"
val pluginPackageName = "org.tommasocretu.markerar"

android {
    namespace = pluginPackageName
    compileSdk = 33
    buildToolsVersion = "33.0.2"

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 24

        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot Android library: compile-only, provided at runtime by the app.
    implementation("org.godotengine:godot:4.2.0.stable")
    // OpenCV bindings: compile-only here, injected in the app build by the
    // export plugin (see export_scripts_template/export_plugin.gd).
    implementation("org.opencv:opencv:4.12.0")
}

// -- Addon layout --------------------------------------------------------------
//
// Collects the EditorExportPlugin scripts and the assembled AARs into the
// addon layout consumed by the Godot project (ar-camera_godot/addons/MarkerARPlugin).
// tools/build_marker_ar.sh copies this directory into the project.

val addonDir = layout.buildDirectory.dir("addon/$pluginName")

val copyExportScripts by tasks.registering(Copy::class) {
    description = "Copies the export scripts into the generated addon directory"
    from("export_scripts_template")
    into(addonDir)
}

val copyDebugAar by tasks.registering(Copy::class) {
    description = "Copies the debug AAR into the generated addon directory"
    from(layout.buildDirectory.dir("outputs/aar")) {
        include("$pluginName-debug.aar")
    }
    into(addonDir.map { it.dir("bin/debug") })
}

val copyReleaseAar by tasks.registering(Copy::class) {
    description = "Copies the release AAR into the generated addon directory"
    from(layout.buildDirectory.dir("outputs/aar")) {
        include("$pluginName-release.aar")
    }
    into(addonDir.map { it.dir("bin/release") })
}

tasks.named("assemble") {
    finalizedBy(copyExportScripts, copyDebugAar, copyReleaseAar)
}
