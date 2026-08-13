package me.itousouta.itou_md

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "itou_md/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Whether this app is allowed to install unknown apps (the
                    // pre-check for launching the system installer on Android
                    // 8+; missing permission makes the install screen silently
                    // never appear).
                    "canRequestPackageInstalls" ->
                        result.success(packageManager.canRequestPackageInstalls())
                    // Opens the system "allow installing unknown apps" screen
                    // for this app.
                    "openUnknownAppSourcesSettings" -> {
                        openUnknownAppSourcesSettings()
                        result.success(null)
                    }
                    // The device's supported ABIs, most-preferred first (e.g.
                    // ["arm64-v8a", "armeabi-v7a"]) — releases ship one APK
                    // per ABI to avoid every install carrying every other
                    // architecture's native code, so the updater needs this
                    // to pick the matching asset.
                    "supportedAbis" ->
                        result.success(Build.SUPPORTED_ABIS.toList())
                    else -> result.notImplemented()
                }
            }
    }

    private fun openUnknownAppSourcesSettings() {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } catch (_: Exception) {
            // Fall back to the generic app details page if the dedicated
            // screen is unavailable on this device.
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS))
        }
    }
}
